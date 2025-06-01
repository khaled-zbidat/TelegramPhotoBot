import flask
from flask import request
import os
from polybot.bot import Bot, ImageProcessingBot
#from bot import Bot, QuoteBot, ImagessProcesssssingBot
#S3 update 1 
app = flask.Flask(_name_)

TELEGRAM_BOT_TOKEN = os.environ['TELEGRAM_BOT_TOKEN']
BOT_APP_URL = os.environ['BOT_APP_URL']


@app.route('/', methods=['GET'])
def index():
    return 'Ok'


@app.route(f'/{TELEGRAM_BOT_TOKEN}/', methods=['POST'])
def webhook():
    req = request.get_json()
    bot.handle_message(req['message'])
    return 'Ok'


if _name_ == "_main_":
    bot = ImageProcessingBot(TELEGRAM_BOT_TOKEN,"https://khaled_nginx.fursa.click")

    app.run(host='0.0.0.0', port=8443)