import telebot
from loguru import logger
import os
import time
import tempfile
from telebot.types import InputFile
from img_proc import Img


class Bot:

    def __init__(self, token, telegram_chat_url):
        # create a new instance of the TeleBot class.
        # all communication with Telegram servers are done using self.telegram_bot_client
        self.telegram_bot_client = telebot.TeleBot(token)

        # remove any existing webhooks configured in Telegram servers
        self.telegram_bot_client.remove_webhook()
        time.sleep(0.5)

        # set the webhook URL
        self.telegram_bot_client.set_webhook(url=f'{telegram_chat_url}/{token}/', timeout=60)

        logger.info(f'Telegram Bot information\n\n{self.telegram_bot_client.get_me()}')

    def send_text(self, chat_id, text):
        self.telegram_bot_client.send_message(chat_id, text)

    def send_text_with_quote(self, chat_id, text, quoted_msg_id):
        self.telegram_bot_client.send_message(chat_id, text, reply_to_message_id=quoted_msg_id)

    def is_current_msg_photo(self, msg):
        return 'photo' in msg

    def download_user_photo(self, msg):
        """
        Downloads the photos that sent to the Bot to a temp directory
        :return: Path to the downloaded photo
        """
        if not self.is_current_msg_photo(msg):
            raise RuntimeError(f'Message content of type \'photo\' expected')

        file_info = self.telegram_bot_client.get_file(msg['photo'][-1]['file_id'])
        data = self.telegram_bot_client.download_file(file_info.file_path)
        
        # Use system temp directory instead of hardcoded path
        temp_dir = tempfile.gettempdir()
        folder_name = os.path.join(temp_dir, file_info.file_path.split('/')[0])
        
        if not os.path.exists(folder_name):
            os.makedirs(folder_name)
        
        # Create full path with temp directory
        file_path = os.path.join(temp_dir, file_info.file_path)
        
        # Ensure directory exists for the file
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        
        with open(file_path, 'wb') as photo:
            photo.write(data)

        return file_path

    def send_photo(self, chat_id, img_path):
        if not os.path.exists(img_path):
            raise RuntimeError("Image path doesn't exist")

        self.telegram_bot_client.send_photo(
            chat_id,
            InputFile(img_path)
        )

    def handle_message(self, msg):
        """Bot Main message handler"""
        logger.info(f'Incoming message: {msg}')
        self.send_text(msg['chat']['id'], f'Your original message: {msg["text"]}')


class QuoteBot(Bot):
    def handle_message(self, msg):
        logger.info(f'Incoming message: {msg}')

        if msg["text"] != 'Please don\'t quote me':
            self.send_text_with_quote(msg['chat']['id'], msg["text"], quoted_msg_id=msg["message_id"])

class ImageProcessingBot(Bot):
    def handle_message(self, msg):
        """
        Handles incoming messages, specifically looking for photos with captions
        to apply image processing filters.
         """
        logger.info(f'Incoming message: {msg}')
    
    # Send welcome message
        self.send_text(msg['chat']['id'], f"Hello {msg['chat']['first_name']}! Welcome to the Image Processing Bot.")
        
        # If it's a photo message
        if self.is_current_msg_photo(msg):
            try:
                if 'caption' not in msg or not msg['caption']:
                    self.send_text(
                        msg['chat']['id'], 
                        "Please provide a caption with the image. Available filters are: "
                        "Blur, Contour, Rotate, Segment, Salt and pepper, Concat"
                    )
                    return
                
                caption = msg['caption'].strip().lower()

                # Define available filters (all lowercase for comparison)
                available_filters = ['blur', 'contour', 'rotate', 'segment', 'salt and pepper', 'concat']
                
                # Match the beginning of the caption to one of the available filters
                matched_filter = None
                params = []
                
                for f in available_filters:
                    if caption.startswith(f):
                        matched_filter = f
                        params = caption[len(f):].strip().split()
                        break

                if not matched_filter:
                    self.send_text(
                        msg['chat']['id'], 
                        f"Invalid filter name. Available filters are: {', '.join([f.title() for f in available_filters])}"
                    )
                    return

                # Download the user's photo
                photo_path = self.download_user_photo(msg)
                logger.info(f'Photo downloaded to: {photo_path}')

                # Initialize Img instance
                img = Img(photo_path)
                self.send_text(msg['chat']['id'], f"Applying {matched_filter.title()} filter...")

                # Apply the selected filter
                if matched_filter == 'blur':
                    blur_level = 16
                    if params and params[0].isdigit():
                        blur_level = int(params[0])
                    img.blur(blur_level)

                elif matched_filter == 'contour':
                    img.contour()

                elif matched_filter == 'rotate':
                    rotation_count = 1
                    if params and params[0].isdigit():
                        rotation_count = int(params[0])
                    for _ in range(rotation_count):
                        img.rotate()

                elif matched_filter == 'segment':
                    if hasattr(img, 'segment'):
                        img.segment()
                    else:
                        self.send_text(msg['chat']['id'], "Segment filter is not implemented yet.")
                        return

                elif matched_filter == 'salt and pepper':
                    if hasattr(img, 'salt_n_pepper'):
                        img.salt_n_pepper()
                    else:
                        self.send_text(msg['chat']['id'], "Salt and pepper filter is not implemented yet.")
                        return

                elif matched_filter == 'concat':
                    self.send_text(msg['chat']['id'], "Concat filter requires two images and is not fully supported yet.")
                    return

                # Save and send the filtered image
                temp_dir = tempfile.gettempdir()
                output_filename = os.path.basename(photo_path).split('.')[0] + '_filtered.jpg'
                output_path = os.path.join(temp_dir, output_filename)
                new_image_path = img.save_img(output_path)
                logger.info(f'Processed image saved to: {new_image_path}')
                self.send_photo(msg['chat']['id'], new_image_path)

            except Exception as e:
                logger.error(f"Error processing image: {str(e)}")
                self.send_text(msg['chat']['id'], f"Something went wrong while processing your image: {str(e)}")

        # If it's a command or plain text
        elif 'text' in msg:
            if msg['text'].startswith('/'):
                if msg['text'] == '/start' or msg['text'] == '/help':
                    self.send_text(
                        msg['chat']['id'],
                        "Welcome to the Image Processing Bot!\n\n"
                        "Send me a photo with one of these captions to apply a filter:\n"
                        "- Blur [level]: Apply blur effect (optional blur level)\n"
                        "- Contour: Detect edges in the image\n"
                        "- Rotate [count]: Rotate the image (optional rotation count)\n"
                        "- Segment: Segment the image\n"
                        "- Salt and pepper: Add salt and pepper noise\n"
                        "- Concat: Combine with another image (not fully implemented)\n\n"
                        "Only Blur and Contour filters are fully implemented."
                    )
                else:
                    self.send_text(
                        msg['chat']['id'],
                        "Unknown command. Send /help for available options."
                    )
            else:
                self.send_text(
                    msg['chat']['id'],
                    "Please send me a photo with a caption to apply image filters.\n"
                    "Available filters: Blur, Contour, Rotate, Segment, Salt and pepper, Concat"
                )

        # Unknown message type
        else:
            self.send_text(
                msg['chat']['id'],
                "I can only process photos. Please send me a photo with a filter caption."
            )
