import telebot
from loguru import logger
import os
import time
import tempfile
from telebot.types import InputFile
from polybot.img_proc import Img
import requests
import boto3
from botocore.exceptions import ClientError
import uuid
from datetime import datetime

class Bot:
    def __init__(self, token, telegram_chat_url):
        self.telegram_bot_client = telebot.TeleBot(token)
        self.telegram_bot_client.remove_webhook()
        time.sleep(0.5)
        self.telegram_bot_client.set_webhook(
            url=f'{telegram_chat_url}/{token}/',
            timeout=60
        )
        logger.info(f'Telegram Bot information\n\n{self.telegram_bot_client.get_me()}')

    def send_text(self, chat_id, text):
        try:
            self.telegram_bot_client.send_message(chat_id, text)
        except Exception as e:
            print(f"Error sending message: {e}")

    def send_text_with_quote(self, chat_id, text, quoted_msg_id):
        self.telegram_bot_client.send_message(chat_id, text, reply_to_message_id=quoted_msg_id)

    def is_current_msg_photo(self, msg):
        return 'photo' in msg

    def download_user_photo(self, msg):
        if not self.is_current_msg_photo(msg):
            raise RuntimeError(f'Message content of type \'photo\' expected')

        file_info = self.telegram_bot_client.get_file(msg['photo'][-1]['file_id'])
        data = self.telegram_bot_client.download_file(file_info.file_path)

        temp_dir = tempfile.gettempdir()
        folder_name = os.path.join(temp_dir, file_info.file_path.split('/')[0])
        if not os.path.exists(folder_name):
            os.makedirs(folder_name)

        file_path = os.path.join(temp_dir, file_info.file_path)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, 'wb') as photo:
            photo.write(data)

        return file_path

    def send_photo(self, chat_id, img_path):
        if not os.path.exists(img_path):
            raise RuntimeError("Image path doesn't exist")

        self.telegram_bot_client.send_photo(chat_id, InputFile(img_path))

    def handle_message(self, msg):
        logger.info(f'Incoming message: {msg}')
        self.send_text(msg['chat']['id'], f'Your original message: {msg["text"]}')


class ImageProcessingBot(Bot):
    def __init__(self, token, telegram_chat_url):
        super().__init__(token, telegram_chat_url)
        self.concat_buffer = {}
        
        # Initialize S3 client
        self.s3_client = boto3.client(
            's3',
            aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
            aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
            region_name=os.getenv('AWS_REGION', 'us-east-1')
        )
        self.s3_bucket = os.getenv('S3_BUCKET_NAME')
        
        if not all([os.getenv('AWS_ACCESS_KEY_ID'), os.getenv('AWS_SECRET_ACCESS_KEY'), self.s3_bucket]):
            logger.error("Missing AWS credentials or S3 bucket name in environment variables")
            raise ValueError("AWS S3 configuration is incomplete")

    def upload_to_s3(self, file_path, object_name=None):
        """Upload a file to S3 bucket"""
        if object_name is None:
            # Generate unique filename with timestamp and UUID
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            unique_id = str(uuid.uuid4())[:8]
            file_extension = os.path.splitext(file_path)[1]
            object_name = f"images/{timestamp}_{unique_id}{file_extension}"

        try:
            self.s3_client.upload_file(file_path, self.s3_bucket, object_name)
            logger.info(f"File uploaded successfully to S3: {object_name}")
            return object_name
        except ClientError as e:
            logger.error(f"Failed to upload file to S3: {e}")
            return None

    def download_from_s3(self, object_name, local_path):
        """Download a file from S3 bucket"""
        try:
            self.s3_client.download_file(self.s3_bucket, object_name, local_path)
            logger.info(f"File downloaded successfully from S3: {object_name}")
            return True
        except ClientError as e:
            logger.error(f"Failed to download file from S3: {e}")
            return False

    def send_to_yolo_service(self, image_name):
        """Send image name to YOLO service instead of image file"""
        try:
            yolo_url = os.getenv("YOLO_URL")
            
            # Send only the image name in the request body
            payload = {"image_name": image_name}
            
            response = requests.post(yolo_url, json=payload, timeout=30)
            
            if response.status_code == 200:
                return response.text
            else:
                logger.error(f"YOLO service returned status {response.status_code}: {response.text}")
                return "Prediction failed: YOLO service returned non-200 status."
        except Exception as e:
            logger.error(f"Failed to get prediction from YOLO service: {str(e)}")
            return "Prediction failed due to server error."

    def handle_message(self, msg):
        logger.info(f'Incoming message: {msg}')
        
        if 'chat' not in msg:
            print("Warning: Message missing 'chat' field, skipping...")
            return
        
        chat_id = msg['chat']['id']
        self.send_text(chat_id, f"Hello {msg['from']['first_name']}! Welcome to the Image Processing Bot.")

        if self.is_current_msg_photo(msg):
            try:
                if 'caption' not in msg or not msg['caption']:
                    self.send_text(
                        chat_id,
                        "Please provide a caption with the image. Available filters are: "
                        "Blur, Contour, Rotate, Segment, Salt and pepper, Concat, Predict"
                    )
                    return

                caption = msg['caption'].strip().lower()
                available_filters = ['blur', 'contour', 'rotate', 'segment', 'salt and pepper', 'concat', 'predict']
                matched_filter = None
                params = []

                for f in available_filters:
                    if caption.startswith(f):
                        matched_filter = f
                        params = caption[len(f):].strip().split()
                        break

                if not matched_filter:
                    self.send_text(chat_id, f"Invalid filter. Available: {', '.join(f.title() for f in available_filters)}")
                    return

                # Download the photo locally first
                photo_path = self.download_user_photo(msg)
                logger.info(f'Photo downloaded to: {photo_path}')

                # Upload image to S3
                self.send_text(chat_id, "Uploading image to S3...")
                s3_object_name = self.upload_to_s3(photo_path)
                
                if not s3_object_name:
                    self.send_text(chat_id, "Failed to upload image to S3. Please try again.")
                    return

                logger.info(f'Image uploaded to S3: {s3_object_name}')

                if matched_filter == 'predict':
                    self.send_text(chat_id, "Sending image to YOLO prediction service...")
                    prediction_result = self.send_to_yolo_service(s3_object_name)
                    self.send_text(chat_id, f"Prediction: {prediction_result}")

                elif matched_filter != 'concat':
                    img = Img(photo_path)
                    self.send_text(chat_id, f"Applying {matched_filter.title()} filter...")

                    if matched_filter == 'blur':
                        blur_level = int(params[0]) if params and params[0].isdigit() else 16
                        img.blur(blur_level)

                    elif matched_filter == 'contour':
                        img.contour()

                    elif matched_filter == 'rotate':
                        rotation_count = int(params[0]) if params and params[0].isdigit() else 1
                        for _ in range(rotation_count):
                            img.rotate()

                    elif matched_filter == 'segment' and hasattr(img, 'segment'):
                        img.segment()

                    elif matched_filter == 'salt and pepper' and hasattr(img, 'salt_n_pepper'):
                        img.salt_n_pepper()

                    else:
                        self.send_text(chat_id, f"{matched_filter.title()} filter is not implemented.")
                        return

                    output_path = os.path.join(tempfile.gettempdir(), os.path.basename(photo_path).split('.')[0] + '_filtered.jpg')
                    new_image_path = img.save_img(output_path)
                    
                    # Upload processed image to S3
                    processed_s3_name = self.upload_to_s3(new_image_path)
                    if processed_s3_name:
                        logger.info(f'Processed image uploaded to S3: {processed_s3_name}')
                    
                    self.send_photo(chat_id, new_image_path)

                else:  # concat
                    if chat_id in self.concat_buffer:
                        first_s3_name = self.concat_buffer.pop(chat_id)
                        
                        # Download first image from S3
                        first_temp_path = os.path.join(tempfile.gettempdir(), f'concat_first_{int(time.time())}.jpg')
                        if self.download_from_s3(first_s3_name, first_temp_path):
                            img1 = Img(first_temp_path)
                            img2 = Img(photo_path)
                            img1.concat(img2)
                            output_path = os.path.join(tempfile.gettempdir(), f'concat_{int(time.time())}.jpg')
                            result = img1.save_img(output_path)
                            
                            # Upload concatenated image to S3
                            concat_s3_name = self.upload_to_s3(result)
                            if concat_s3_name:
                                logger.info(f'Concatenated image uploaded to S3: {concat_s3_name}')
                            
                            self.send_text(chat_id, "Images concatenated successfully!")
                            self.send_photo(chat_id, result)
                        else:
                            self.send_text(chat_id, "Failed to download first image from S3.")
                    else:
                        self.concat_buffer[chat_id] = s3_object_name
                        self.send_text(chat_id, "First image received and uploaded to S3. Please send the second image with caption 'concat'.")

            except Exception as e:
                logger.error(f"Error processing image: {str(e)}")
                self.send_text(chat_id, f"Error processing image: {str(e)}")

        elif 'text' in msg:
            if msg['text'].startswith('/'):
                if msg['text'] in ['/start', '/help']:
                    self.send_text(
                        chat_id,
                        "Welcome to the Image Processing Bot!\n\n"
                        "Send me a photo with one of these captions:\n"
                        "- Blur [level]\n"
                        "- Contour\n"
                        "- Rotate [count]\n"
                        "- Segment\n"
                        "- Salt and pepper\n"
                        "- Concat (requires two images)\n"
                        "- Predict (runs YOLO prediction)\n"
                    )
                else:
                    self.send_text(chat_id, "Unknown command. Send /help for options.")
            else:
                self.send_text(chat_id, "Please send a photo with a caption. Type /help for filter options.")

        else:
            self.send_text(chat_id, "I can only process photo messages.")