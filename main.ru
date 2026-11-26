
import os
import sqlite3
from datetime import datetime

import telebot
from telebot import types

TOKEN = os.getenv("BOT_TOKEN")
if not TOKEN:
    raise RuntimeError("BOT_TOKEN sozlamasi topilmadi")

bot = telebot.TeleBot(TOKEN)

DB = "razval.db"

MODELS = [
    "Chevrolet Cobalt",
    "Chevrolet Gentra",
    "Chevrolet Nexia 3",
    "Chevrolet Lacetti",
    "Chevrolet Damas",
    "Chevrolet Spark",
    "Chevrolet Onix",
    "Chevrolet Tracker",
    "Chevrolet Malibu",
    "Chevrolet Equinox",
    "Boshqa model"
]

def init_db():
    with sqlite3.connect(DB) as con:
        con.execute("""
        CREATE TABLE IF NOT EXISTS cars (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model TEXT,
            plate TEXT,
            mileage INTEGER,
            master TEXT,
            debt REAL,
            car_photo TEXT,
            work_photo TEXT,
            date TEXT,
            worker_id INTEGER
        )
        """)

init_db()
data = {}

def main_menu(chat_id):
    kb = types.ReplyKeyboardMarkup(resize_keyboard=True)
    kb.row("➕ Новая машина")
    kb.row("📋 История автомобилей")
    bot.send_message(chat_id, "Выберите действие:", reply_markup=kb)

@bot.message_handler(commands=["start"])
def start(message):
    bot.send_message(
        message.chat.id,
        "Добро пожаловать в журнал Dehqonobod 3D Razval!"
    )
    main_menu(message.chat.id)

@bot.message_handler(commands=["cancel"])
def cancel(message):
    data.pop(message.chat.id, None)
    bot.send_message(message.chat.id, "Отменено.")
    main_menu(message.chat.id)

@bot.message_handler(func=lambda m: m.text == "➕ Новая машина")
def new_car(message):
    chat_id = message.chat.id
    data[chat_id] = {}

    kb = types.ReplyKeyboardMarkup(resize_keyboard=True)
    for model in MODELS:
        kb.add(model)

    msg = bot.send_message(
        chat_id, "Выберите марку и модель автомобиля:",
        reply_markup=kb
    )
    bot.register_next_step_handler(msg, get_model)

def get_model(message):
    chat_id = message.chat.id
    if chat_id not in data:
        return

    data[chat_id]["model"] = message.text
    msg = bot.send_message(chat_id, "Введите номер автомобиля:")
    bot.register_next_step_handler(msg, get_plate)

def get_plate(message):
    chat_id = message.chat.id
    data[chat_id]["plate"] = message.text.strip()
    msg = bot.send_message(chat_id, "Введите пробег (км):")
    bot.register_next_step_handler(msg, get_mileage)

def get_mileage(message):
    chat_id = message.chat.id
    try:
        mileage = int(message.text.replace(" ", ""))
        if mileage < 0:
            raise ValueError
    except ValueError:
        msg = bot.send_message(chat_id, "Введите пробег числом:")
        bot.register_next_step_handler(msg, get_mileage)
        return

    data[chat_id]["mileage"] = mileage
    msg = bot.send_message(chat_id, "Введите имя мастера:")
    bot.register_next_step_handler(msg, get_master)

def get_master(message):
    chat_id = message.chat.id
    data[chat_id]["master"] = message.text.strip()
    msg = bot.send_message(chat_id, "Введите долг клиента (0, если нет):")
    bot.register_next_step_handler(msg, get_debt)

def get_debt(message):
    chat_id = message.chat.id
    try:
        debt = float(message.text.replace(" ", "").replace(",", "."))
        if debt < 0:
            raise ValueError
    except ValueError:
        msg = bot.send_message(chat_id, "Введите сумму числом:")
        bot.register_next_step_handler(msg, get_debt)
        return

    data[chat_id]["debt"] = debt
    msg = bot.send_message(
        chat_id, "Отправьте фотографию автомобиля:"
    )
    bot.register_next_step_handler(msg, get_car_photo)

def get_car_photo(message):
    chat_id = message.chat.id
    if not message.photo:
        msg = bot.send_message(chat_id, "Пожалуйста, отправьте фото автомобиля.")
        bot.register_next_step_handler(msg, get_car_photo)
        return

    data[chat_id]["car_photo"] = message.photo[-1].file_id
    msg = bot.send_message(
        chat_id, "Теперь отправьте фотографию выполненной работы:"
    )
    bot.register_next_step_handler(msg, get_work_photo)

def get_work_photo(message):
    chat_id = message.chat.id
    if not message.photo:
        msg = bot.send_message(chat_id, "Пожалуйста, отправьте фото выполненной работы.")
        bot.register_next_step_handler(msg, get_work_photo)
        return

    item = data[chat_id]
    item["work_photo"] = message.photo[-1].file_id
    item["date"] = datetime.now().strftime("%d.%m.%Y %H:%M")

    with sqlite3.connect(DB) as con:
        con.execute("""
        INSERT INTO cars
        (model, plate, mileage, master, debt,
         car_photo, work_photo, date, worker_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            item["model"], item["plate"], item["mileage"],
            item["master"], item["debt"],
            item["car_photo"], item["work_photo"],
            item["date"], message.from_user.id
        ))

    bot.send_message(
        chat_id,
        "✅ Автомобиль успешно сохранён!\n\n"
        f"Модель: {item['model']}\n"
        f"Номер: {item['plate']}\n"
        f"Пробег: {item['mileage']} км\n"
        f"Мастер: {item['master']}\n"
        f"Долг: {item['debt']:g} сум\n"
        f"Дата: {item['date']}"
    )

    bot.send_photo(chat_id, item["car_photo"], caption="Автомобиль")
    bot.send_photo(chat_id, item["work_photo"], caption="Выполненная работа")

    data.pop(chat_id, None)
    main_menu(chat_id)

@bot.message_handler(func=lambda m: m.text == "📋 История автомобилей")
def history(message):
    with sqlite3.connect(DB) as con:
        rows = con.execute("""
        SELECT id, model, plate, mileage, master, debt, date
        FROM cars ORDER BY id DESC LIMIT 15
        """).fetchall()

    if not rows:
        bot.send_message(message.chat.id, "Записей пока нет.")
        return

    for r in rows:
        bot.send_message(
            message.chat.id,
            f"Запись №{r[0]}\n"
            f"Модель: {r[1]}\n"
            f"Номер: {r[2]}\n"
            f"Пробег: {r[3]} км\n"
            f"Мастер: {r[4]}\n"
            f"Долг: {r[5]:g} сум\n"
            f"Дата: {r[6]}"
        )

bot.infinity_polling(skip_pending=True)
