this on claude made it work : the p[roblem wre in teh certificate those 3 linmes made magic : 
dsfsdgdfgdfgdfgdfdfgdfgdf
fgdfgdfgdfgdfgdf
sudo apt update
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d khaled.fursa.click

this on claude made it work : the p[roblem wre in teh certificate those 3 linmes made magic : 

sudo apt update
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d khaled.fursa.click

curl -F "url=https://khaled.fursa.click/webhook" https://api.telegram.org/bot<Token>/setWebhook
{"ok":true,"result":true,"description":"Webhook was set"}

curl https://api.telegram.org/bot<Token>>/getWebhookInfo
{"ok":true,"result":{"url":"https://khaled.fursa.click/webhook","has_custom_certificate":false,"pending_update_count":3,"max_connections":40,"ip_address":"3.68.255.226"}}

Excellent! 🎉 You successfully got a valid SSL certificate for `khaled.fursa.click`! Now you need to update your bot configuration to use the new domain.

## Steps to Complete the Fix:
git a
### 1. Update Your Bot Configuration

You need to update your bot code to use the new domain. Update these files on your **bot server** (not the nginx server):### 2. Update Your Start Script

Update your `start_dev.sh` script:### 3. Commands to Run on Your Bot Server

Run these commands on your **bot server** (ip-10-0-17-41):

```bash
# Navigate to your project
cd ~/TelegramPhotoBot/polybot

# Update app.py - replace the old domain with new domain
sudo sed -i 's/khaled_nginx\.fursa\.click/khaled.fursa.click/g' app.py

# Update start_dev.sh - replace the old domain with new domain  
sudo sed -i 's/khaled_nginx\.fursa\.click/khaled.fursa.click/g' start_dev.sh

# Update bot.py if it contains the old domain
sudo sed -i 's/khaled_nginx\.fursa\.click/khaled.fursa.click/g' bot.py

# Check the changes were applied
grep -r "fursa.click" .
```

### 4. Set the New Webhook

Now set the webhook with the new valid domain:

```bash
curl -X POST \
  "https://api.telegram.org/bot token/setWebhook" \
  -d "url=https://khaled.fursa.click/bottoken/"
```

### 5. Restart Your Bot Service

```bash
sudo systemctl restart polyservice
```

### 6. Verify Everything is Working

```bash
# 1. Check webhook info
curl "https://api.telegram.org/bottoken/getWebhookInfo"

# 2. Test your new domain (should work without -k flag now)
curl https://khaled.fursa.click/

# 3. Test your webhook endpoint with GET (should return 405 Method Not Allowed - this is correct)
curl "https://khaled.fursa.click/bottoken/"

# 4. Check if your Flask app is running
curl http://localhost:8443/
```

### 7. Test Your Bot

Once everything is updated and restarted:
1. Open Telegram
2. Find your bot
3. Send it a message like "Hello"
4. Send it a photo with caption "contour"

You should see the bot responding now that you have a valid SSL certificate!

The key changes:
- ❌ Old: `khaled_nginx.fursa.click` (invalid underscore)
- ✅ New: `khaled.fursa.click` (valid domain with SSL certificate)]


Certaisnly! Here are the essential systemctl commands to manage your telegrambot service on Ubuntu:

🔄 Restart the Servicess
To restart the telegrambot service:

bash
Copy
Edit
sudo systemctl restart telegrambot
🔄 Reload the Service
If the service supportsxx reloading its configuration without a full restart:

bash
Copy
Edit
sudo systemctl reload telegrambot
✅ Check the Service Status
To view the current status of the telegrambot service:

bash
Copy
Edit
sudo systemctl status telegrambot
📋 View Logs for the Service
To monitor the logs of the telegrambot service in real-time:

bash
Copy
Edit
journalctl -u telegrambot -f
⚙️ Enable the Service at Boot
To ensure the telegrambot service starts automatically on boot:

bash
Copy
Edit
sudo systemctl enable telegrambot
❌ Disable the Service at Boot
To prevent the telegrambot service from starting automatically on boot:

bash
Copy
Edit
sudo systemctl disable telegrambot
🔍 List All Services
To list all systemd services:

bash
Copy
Edit
systemctl list-unit-files --type=service
Let me know if you need assistance with creating a script to automate these commands or if you have any other questions!

also this ::::------------------
::::-------------------------
:----------------------
# Fix Telegram Bot SSL Certificate Issue

## Problem Identified
- Webhook has `"has_custom_certificate": true` but should be `false`
- SSL certificate verification is failing
- 13 pending webhook deliveries are queued

## Step 1: Delete Current Webhook (Clean Slate)

On your **bot server** (ip-10-0-17-41):

```bash
# Delete the current webhook completely
curl -X POST "https://api.telegram.org/bottoken/deleteWebhook"

# Wait for cleanup
sleep 10

# Verify it's deleted
curl "https://api.telegram.org/bottoken/getWebhookInfo"
```

## Step 2: Test SSL Certificate Properly

```bash
# Test the SSL certificate from your bot server
curl -v https://khaled.fursa.click/ 2>&1 | grep -E "(certificate|SSL|TLS)"

# Test from external perspective
curl -I https://khaled.fursa.click/
```

## Step 3: Set Webhook Without Custom Certificate

```bash
# Set webhook using Let's Encrypt certificate (not custom)
curl -X POST "https://api.telegram.org/bottoken/setWebhook" \
  -d "url=https://khaled.fursa.click/bottoken/" \
  -d "drop_pending_updates=true"

# The drop_pending_updates=true will clear the 13 pending updates
```

## Step 4: Verify Webhook is Set Correctly

```bash
curl "https://api.telegram.org/bottoken/getWebhookInfo"
```

**Expected Result:**
```json
{
  "ok": true,
  "result": {
    "url": "https://khaled.fursa.click/bottoken/",
    "has_custom_certificate": false,
    "pending_update_count": 0,
    "max_connections": 40
  }
}
```

## Step 5: Fix Connection Stability

On your **bot server**, ensure the service is stable:

```bash
# Check if service is running consistently
sudo systemctl status polyservice

# If needed, restart with better stability
sudo systemctl restart polyservice

# Monitor for connection issues
sudo journalctl -u polyservice -f
```

## Step 6: Test Bot Functionality

```bash
# Test webhook endpoint
curl -X POST https://khaled.fursa.click/bottoken/ \
  -H "Content-Type: application/json" \
  -d '{"message": {"text": "test"}}'

# Should return: {"message":"webhook received"}
```

## Step 7: Test with Telegram

1. Open Telegram
2. Find your bot (@photos_filter_bot)
3. Send: `/start`
4. Send: `hello`
5. Send a photo with caption: `contour`

## Why This Happened

The issue occurred because:
1. **Custom Certificate Flag**: Somehow the webhook was set with a custom certificate flag
2. **Certificate Mismatch**: Telegram expects the certificate to match exactly
3. **Pending Updates**: 13 failed webhook attempts were queued, preventing new ones

## Prevention

To avoid this in the future:
- Always use `drop_pending_updates=true` when setting webhooks after changes
- Never set custom certificates unless you specifically uploaded one
- Monitor webhook info regularly with `getWebhookInfo`

## Quick Commands Summary

Run these in order:

```bash
# 1. Delete webhook
curl -X POST "https://api.telegram.org/bottoken/deleteWebhook"

# 2. Wait
sleep 10

# 3. Set new webhook with drop_pending_updates
curl -X POST "https://api.telegram.org/bottoken/setWebhook" \
  -d "url=https://khaled.fursa.click/bottoken/" \
  -d "drop_pending_updates=true"

# 4. Verify
curl "https://api.telegram.org/bottoken/getWebhookInfo"

# 5. Test bot in Telegram
```



------------------------
--------------------------\
---------------------------


# The Polybot Service: Python Project [![][autotest_badge]][autotest_workflow]

## Background

In this project, you develop a Python chatbot application which applies filters to images send by users to a Telegram bot. 

Here is a short demonstration:

![app demo](.github/python_project_demo.gif)

## Preliminaries

1. Create this repository in your account by clicking on **Use this template**, then **Create a new repository**.  
2. Clone your repository by:
   ```bash
   git clone https://github.com/<your-username>/<your-project-repo-name>
   ```
   Change `<your-username>` and `<your-project-repo-name>` according to your GitHub username and the name you gave to your created repo. E.g. `git clone https://github.com/johndoe/PolybotServicePython`.
3. Open the repo as a code project in your favorite IDE (Pycharm, VSCode, etc..).
   It is also a good practice to create an isolated Python virtual environment specifically for your project ([see here how to do it in PyCharm](https://www.jetbrains.com/help/pycharm/creating-virtual-environment.html)).

Later on, you are **required** to change the `README.md` file content to provide relevant information about your service project, e.g. how to launch the app, main features, etc.

Let's get started...

## Intro to image processing

Reference: https://ai.stanford.edu/~syyeung/cvweb/tutorial1.html

### What is a digital image?


If we take a closer look on a digital image, we will notice it comprised of individual pixels, 
each pixel has its own value. For a grayscale image, each pixel would have an **intensity** value between 0 and 255, with 0 being black and 255 being white. 

![][python_project_pixel]

A grayscale image, then, can be represented as a matrix of pixel values:

![][python_project_imagematrix]

A color image is just a simple extension of this. The colors are constructed from a combination of Red, Green, and Blue (RGB). Instead of one matrix of pixel values, we use 3 different matrix, one for the Red (R) values, one for Green (G), and one Blue (B) values. 

<img src="https://exit-zero-academy.github.io/DevOpsTheHardWayAssets/img/python_project_colorpixels.png" width="50%">

As can be seen, each pixel of the image has three channels, represent the red, green, blue values. 

Python-wise, a digital grayscale image is essentially a matrix (list of lists):

![][python_project_pythonimage]

Each element in the `image` list is a list represented a **row** of pixels. 

### Image filtering

Filtered images are ubiquitous in our social media feeds, news articles, books—everywhere!
Image filtering is a technique in image processing that involves modifying or enhancing an image by applying a filter to it.
Filters can be used to remove noise, sharpen edges, blur or smooth the image, or highlight specific features or details, among other effects.

Python-wise, image filtering is as simple as manipulate the pixel values. 

## The `Img` class

Under `polybot/img_proc.py`, the `Img` class is designed for image filtering on grayscale images.
Here is a detailed usage instruction for the class:

1. Creating an instance of `Img`:

   Provide the path to the image file as a parameter when creating an instance of the `Img` class, for example:
   
   ```python
   my_img = Img('path/to/image.jpg')
   ```

2. Saving the modified image:
   After performing operations on the image, you can save the modified image using the `save_img()` method, for example:
   
   ```python
   my_img.save_img()
   ```
   
   This will save the modified grayscale image to a new path with an appended `_filtered` suffix, and uses the same file extension.

### Filters for you to implement

You are instructed to implement at least the following 4 filters: `concat()`, `rotate()`, `salt_n_pepper()`, `segment()`.

On every error (E.g. image path doesn't exist, input image is not an RGB) you should raise a `RuntimeError` exception.


#### Concatenating images

The `concat()` method is meant to concatenate two images together horizontally (side by side).


Implementation instruction for horizontal concatenation:   
- Check the dimensions of both images to ensure they are compatible for concatenation. If the dimensions are not compatible (e.g., different heights), raise a `RuntimeError` exception with informative message.
- Combine the pixel values of both images to create a new image. For horizontal concatenation, combine each row of the first image with the corresponding row of the second image.
- Store the resulting concatenated image in the `self.data` attribute of the instance. 

```python
my_img = Img('path/to/image.jpg')
another_img = Img('path/to/image2.jpg')
my_img.concat(another_img) 
my_img.save_img()   # concatenated image was saved in 'path/to/image_filtered.jpg'
```

Note: you can optionally use the `direction` argument to implement `vertical` concatenation as well.

#### Adding "salt and pepper" noise to the image

The `salt_n_pepper()` noise method applies a type of image distortion that randomly adds isolated pixels with value of either 255 (maximum white intensity) or 0 (minimum black intensity).
The name "salt and pepper" reflects the appearance of these randomly scattered bright and dark pixels, resembling grains of salt and pepper sprinkled on an image.

Implementation instruction:   
 1. Iterate over the pixels of the image by looping through each row and each pixel value.
 2. For each pixel in the image:
     - Randomly generate a number between 0 and 1.
     - If the random number is less than 0.2, set the pixel value to the maximum intensity (255) to represent salt.
     - If the random number is greater than 0.8, set the pixel value to the minimum intensity (0) to represent pepper.
     - If neither condition is met (the random number is in between 0.2 to 0.8), keep the original pixel value without any modification.


```python
my_img = Img('path/to/image.jpg')
my_img.salt_n_pepper() 
my_img.save_img()  # noisy image was saved in 'path/to/image_filtered.jpg'
```

#### Rotating the image

The `rotate()` method rotates an image around its center in a clockwise direction.
    
Implementation remarks:   
The resulting rotated image will have its rows become the columns, and the columns will become the rows. The pixels in the rotated image will be repositioned based on a clockwise rotation around the center of the original image. For example, the first row in the original image will become the last column in the rotated image, the second row will become the second-to-last column, and so on.  

```python
my_img = Img('path/to/image.jpg')
my_img.rotate() 
my_img.rotate()  # rotate again for a 180 degrees rotation
my_img.save_img()   # rotated image was saved in 'path/to/image_filtered.jpg'
```

#### Segmenting the image

The `segment()` method partitions the image into regions where the pixels have similar attributes, so the image is represented in a more simplified manner, and so we can then identify objects and boundaries more easily.

Implementation instruction:   
 1. Iterate over the pixels of the image by looping through each row and each pixel value.
 2. All pixels with an intensity greater than 100 are replaced with a white pixel (intensity 255) and all others are replaced with a black pixel (intensity 0). 

```python
my_img = Img('path/to/image.jpg')
my_img.segment() 
my_img.save_img()
```

### Filters for inspiration

The below two filters was already implemented, you can review these functions to get some inspiration of how might a filter implementation look like. 

#### Blurring the image

The `blur()` method is already implemented. You can control the blurring level `blur_level` argument (default is 16).
   It blurs the image by replacing the value of each pixel by the average of the 16 pixels around him (or any other value, controlled by the `blur_level` argument. The bigger the value, the stronger the blurring level).

```python
my_img = Img('path/to/image.jpg')
my_img.blur()   # or my_img.blur(blur_level=32) for stronger blurring effect
my_img.save_img()
```

#### Creating a contour of the image

The `contour()` method is already implemented. It applies a contour effect to the image by calculating the **differences between neighbor pixels** along each row of the image matrix.

```python
my_img = Img('path/to/image.jpg')
my_img.contour() 
my_img.save_img()
```

## Test your filters locally

Under `polybot/test` you'll find unittests for each filter.

For example, to execute the test suite for the `concat()` filter, run the below command from the root dir of your repo:

```bash
python -m polybot.test.test_concat
```

An alternative way is to run tests from the Pycharm UI. 

## Create a Telegram Bot

1. <a href="https://desktop.telegram.org/" target="_blank">Download</a> and install Telegram Desktop (you can use your phone app as well).
2. Once installed, create your own Telegram Bot by following <a href="https://core.telegram.org/bots/features#botfather">this section</a> to create a bot. Once you have your telegram token you can move to the next step.

**Never** commit your telegram token in Git repo, even if the repo is private.
For now, we will provide the token as an environment variable to your chat app. 
Later on in the course we will learn better approaches to store sensitive data.

## Running the Telegram bot locally

The Telegram app is a flask-based service that responsible for providing a chat-based interface for users to interact with your image processing functionality. 
It utilizes the Telegram Bot API to receive user images and respond with processed images. 

The code skeleton for the bot app is already given to you under `polybot/app.py`.
In order to run the server, you have to [provide 2 environment variables](https://www.jetbrains.com/help/objc/add-environment-variables-and-program-arguments.html#add-environment-variables):

1. `TELEGRAM_BOT_TOKEN` which is your bot token.
2. `BOT_APP_URL` which is your app public URL provided by Ngrok (will be discussed soon).

Implementing bot logic involves running a local Python script that listens for updates from Telegram servers.
When a user sends a message to the bot, Telegram servers forward the message to the Python app using a method called **webhook** (**long-polling** and **websocket** are other possible methods which wouldn't be used in this project).
The Python app processes the message, executes the desired logic, and may send a response back to Telegram servers, which then delivers the response to the user.

The webhook method consists of simple two steps:

Setting your chat app URL in Telegram Servers:

![][python_project_webhook1]

Once the webhook URL is set, Telegram servers start sending HTTPS POST requests to the specified webhook URL whenever there are updates, such as new messages or events, for the bot. 

![][python_project_webhook2]


You've probably noticed that setting `localhost` URL as the webhook for a Telegram bot can be problematic because Telegram servers need to access the webhook URL over the internet to send updates.
As `localhost` is not accessible externally, Telegram servers won't be able to reach the webhook, and the bot won't receive any updates.

[Ngrok](https://ngrok.com/) can solve this problem by creating a secure tunnel between the local machine (where the bot is running) and a public URL provided by Ngrok.
It exposes the local server to the internet, allowing Telegram servers to reach the webhook URL and send updates to the bot.

Sign-up for the Ngrok service (or any another tunneling service to your choice), then install the `ngrok` agent as [described here](https://ngrok.com/docs/getting-started/#step-2-install-the-ngrok-agent). 

Authenticate your ngrok agent. You only have to do this once:

```bash
ngrok config add-authtoken <your-authtoken>
```

Since the telegram bot service will be listening on port `8443`, start ngrok by running the following command:

```bash
ngrok http 8443
```

Your bot public URL is the URL specified in the `Forwarding` line (e.g. `https://16ae-2a06-c701-4501-3a00-ecce-30e9-3e61-3069.ngrok-free.app`).
Don't forget to set the `BOT_APP_URL` env var to your URL. 

In the next step you'll finally run your bot app.

> [!TIP]
> If you want to keep the same URL each time you use ngrok, [create a static domain on your dashboard](https://dashboard.ngrok.com/cloud-edge/domains) and then use the `--url` flag to ask the ngrok agent to use it.


## Running a simple "echo" Bot - the `Bot` class

Under `polybot/bot.py` you are given a class called `Bot`. This class implements a simple telegram bot, as follows.

The constructor `__init__` receives the `token` and `telegram_chat_url` arguments.
The constructor creates an instance of the `TeleBot` object, which is a pythonic interface to Telegram API. You can use this instance to conveniently communicate with the Telegram servers.
Later, the constructor sets the webhook URL to be the `telegram_chat_url`. 

The `polybot/app.py` is the main app entrypoint. It's nothing but a simple flask webserver that uses a `Bot` instance to handle incoming messages, caught in the `webhook` endpoint function.

The default behavior of the `Bot` class is to "echo" the incoming messages. Try it out!

## Extending the echo bot - the `QuoteBot` class

In `bot.py` you are given a class called `QuoteBot` which **inherits** from `Bot`.
Upon incoming messages, this bot echoing the message while quoting the original message, unless the user is asking politely not to quote.

In `app.py`, change the instantiated instance to the `QuoteBot`:

```diff
if __name__ == "__main__":
-   bot = Bot(TELEGRAM_BOT_TOKEN, BOT_APP_URL)
+   bot = QuoteBot(TELEGRAM_BOT_TOKEN, BOT_APP_URL)
    app.run(host='0.0.0.0', port=8443)
```

Run this bot and check its behavior.

## Build your image processing bot - the `ImageProcessingBot` class

In `bot.py` you are given a class called `ImageProcessingBot` which **inherits** from `Bot`, again.
Upon incoming **photo messages**, this bot downloads the photos and processes them according to the **`caption`** field provided with the message.
The bot will then send the processed image to the user.

A few notes:

- Inside the `ImageProcessingBot` class, override `handle_message` method and implement the needed functionality.
- Remember that by inheriting the `Bot` class, you can use all of its methods (such as `send_text`, `download_user_photo`, `send_photo`...). 
- Possible `caption` values are: `['Blur', 'Contour', 'Rotate', 'Segment', 'Salt and pepper', 'Concat']`.
- Handle potential errors using `try... except... `. Send an appropriate message to the user (E.g. "something went wrong... please try again").
- Set a timeout when sending a message to Telegram.
- Use `logger` to log important information in your app.
- Your bot should support the `Blur` and `Contour` filters (those filters have already implemented for you). 

Test your bot on real photos and make sure it's functioning properly.

> [!TIP]
> When working with Telegram's API, you might encounter situations where your code encounters errors while processing incoming messages. In such cases, Telegram's server will automatically retry sending messages that were not responded to with a status code of 200. This retry mechanism is designed to ensure the reliable delivery of messages.
> If you find that your bot is receiving repeated messages due to this retry mechanism, just review your code and identify any errors or issues that might be causing the message processing failures. 

## Test your bot locally

You can test your bot logic locally by executing the below unittests from the root directory of your project:

```bash
python -m polybot.test.test_telegram_bot
```

## Extend your bot functionality

Add any functionality you wish to your bot...

- Greet the user.
- Add some informative message when user sends photos without captions or with invalid caption value.
- Add your own filters.
- Extend the functionality of the filters, e.g. allow users to specify "Rotate 2" to rotate the image twice).

**Go wild!!!** 


## Submission

Time to submit your solution for testing.

1. Commit and push your changes.
1. In [GitHub Actions][github_actions], watch the automated test execution workflow (enable Actions if needed). 
   If there are any failures, click on the failed job and **read the test logs carefully**. Fix your solution, commit and push again.


## Good Luck

[DevOpsTheHardWay]: https://github.com/exit-zero-academy/DevOpsTheHardWay
[autotest_badge]: ../../actions/workflows/project_auto_testing.yaml/badge.svg?event=push
[autotest_workflow]: ../../actions/workflows/project_auto_testing.yaml/
[clone_pycharm]: https://www.jetbrains.com/help/pycharm/set-up-a-git-repository.html#clone-repo
[github_actions]: ../../actions

[python_project_demo]: https://exit-zero-academy.github.io/DevOpsTheHardWayAssets/img/python_project_demo.gif
[python_project_pixel]: https://exit-zero-academy.github.io/DevOpsTheHardWayAssets/img/python_project_pixel.gif
[python_project_imagematrix]: https://exit-zero-academy.github.io/DevOpsTheHardWayAssets/img/python_project_imagematrix.png
[python_project_pythonimage]: https://exit-zero-academy.github.io/DevOpsTheHardWayAssets/img/python_project_pythonimage.png
[python_project_webhook1]: https://exit-zero-academy.github.io/DevOpsTheHardWayAssets/img/python_project_webhook1.png
[python_project_webhook2]: https://exit-zero-academy.github.io/DevOpsTheHardWayAssets/img/python_project_webhook2.png


steps:
Absolutely, Khaled. Here's a **complete summary** of everything you need to do to make your **Telegram bot run as a systemd service** and auto-restart correctly.

---

## ✅ Goal

Run your Telegram bot located at `/home/ubuntu/TelegramPhotoBot/polybot/start.sh` as a **systemd service**, so that it:

* Loads required environment variables
* Activates a virtual environment
* Starts the bot automatically
* Restarts on failure

---

## 📁 1. Make the `start.sh` script executable

```bash
chmod +x /home/ubuntu/TelegramPhotoBot/polybot/start.sh
```

---

## 🧠 2. Ensure `start.sh` has the correct contents

Edit this file:

```bash
nano /home/ubuntu/TelegramPhotoBot/polybot/start.sh
```

And ensure it contains:

```bash
#!/bin/bash

# Load environment variables
set -a
source /etc/telegram_bot_env
set +a

# Activate virtual environment
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate

# Start the bot
python3 -m polybot.app
```

> ✅ Make sure `/etc/telegram_bot_env` exists and contains your needed environment variables (like the bot token, etc.)

---

## 🧾 3. Create the systemd service file

Create the service file:

```bash
sudo nano /etc/systemd/system/telegrambot.service
```

Paste the following:

```ini
[Unit]
Description=Telegram Photo Bot
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/TelegramPhotoBot
ExecStart=/home/ubuntu/TelegramPhotoBot/polybot/start.sh
Restart=on-failure
EnvironmentFile=/etc/telegram_bot_env

[Install]
WantedBy=multi-user.target
```

> ✅ Make sure paths match your actual project structure
> ✅ `User=ubuntu` should match the user that owns the bot directory and virtualenv

---

## 🔄 4. Reload systemd and start the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable telegrambot
sudo systemctl start telegrambot
```

---

## 🧪 5. Check if it worked

```bash
sudo systemctl status telegrambot
```

You should see:

```
Active: active (running)
```

If not, run:

```bash
journalctl -u telegrambot.service -n 50 --no-pager
```

This will show detailed logs of what went wrong.

---

## 🔁 6. Restarting the service after updating code

If you change your bot code or the script, just run:

```bash
sudo systemctl restart telegrambot
```

---

Let me know if you want to add logging or auto-ngrok as part of this too.
