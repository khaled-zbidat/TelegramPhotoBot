class ImageProcessingBot(Bot):
    def __init__(self, token, telegram_chat_url):
        super().__init__(token, telegram_chat_url)
        self.concat_buffer = {}

    def send_to_yolo_service(self, image_path):
        try:
            url = "http://10.0.1.187:8667/predict"
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
        chat_id = msg['chat']['id']
        self.send_text(chat_id, f"Hello {msg['chat']['first_name']}! Welcome to the Image Processing Bot.")

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
