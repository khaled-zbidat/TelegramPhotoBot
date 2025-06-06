import telebot
from loguru import logger
import os
import time
import tempfile
from telebot.types import InputFile
#from polybot.img_proc import Imfgfgfgfgfgfgsssssssssss hhhhhhh
from polybot.img_proc import Img
import requests  

class Bot:
    def __init__(self, token, telegram_chat_url):
        self.telegram_bot_client = telebot.TeleBot(token)
        self.telegram_bot_client.remove_webhook()
        time.sleep(0.5)
        # teh ssl certificat whihc is teh name of is is polybot.crt is in the default ubuntu dir 
        # self.telegram_bot_client.set_webhook(url=f'{telegram_chat_url}/{token}/', timeout=60 , certificate=open("/home/ubuntu/polybot_dev.crt", 'rb'))
        self.telegram_bot_client.set_webhook(
            url=f'{telegram_chat_url}/{token}/',
            timeout=60
        )

        # self.telegram_bot_client.set_webhook(url=f'{telegram_chat_url}/{token}/', timeout=60 , certificate=open("/home/ubuntu/TelegramPhotoBot/polybot/poly_cert.crt", 'r'))
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

    def send_to_yolo_service(self, image_path):
        try:
            yolo_url = os.getenv("YOLO_URL")
            url = yolo_url
            with open(image_path, 'rb') as img_file:
                files = {'file': img_file}
                response = requests.post(url, files=files, timeout=5)
            if response.status_code == 200:
                return response.text
            else:
                return "Prediction failed: YOLO service returned non-200 status."
        except Exception as e:
            logger.error(f"Failed to get prediction from YOLO EC2: {str(e)}")
            return "Prediction failed due to server error."

    def handle_message(self, msg):
        logger.info(f'Incoming message: {msg}')
        # chat_id = msg['chat']['id']# Add error handling for missing chat field
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

                photo_path = self.download_user_photo(msg)
                logger.info(f'Photo downloaded to: {photo_path}')

                if matched_filter == 'predict':
                    self.send_text(chat_id, "Sending image to YOLO prediction service...")
                    prediction_result = self.send_to_yolo_service(photo_path)
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
                    self.send_photo(chat_id, new_image_path)

                else:
                    if chat_id in self.concat_buffer:
                        first_path = self.concat_buffer.pop(chat_id)
                        img1 = Img(first_path)
                        img2 = Img(photo_path)
                        img1.concat(img2)
                        output_path = os.path.join(tempfile.gettempdir(), f'concat_{int(time.time())}.jpg')
                        result = img1.save_img(output_path)
                        self.send_text(chat_id, "Images concatenated successfully!")
                        self.send_photo(chat_id, result)
                    else:
                        self.concat_buffer[chat_id] = photo_path
                        self.send_text(chat_id, "First image received. Please send the second image with caption 'concat'.")

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
