
import os
import sqlite3
from datetime import datetime
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, MessageHandler,
    ConversationHandler, ContextTypes, filters
)

TOKEN = os.getenv("BOT_TOKEN")
ADMIN_ID = int(os.getenv("ADMIN_ID", "0"))
DB = "razval.db"

PLATE, BRAND, MILEAGE, TIRE, SERVICE, PRICE = range(6)
SEARCH = 6

def connect():
    return sqlite3.connect(DB)

def init_db():
    with connect() as db:
        db.execute("""
        CREATE TABLE IF NOT EXISTS cars (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plate TEXT, brand TEXT, mileage TEXT,
            tire TEXT, service TEXT, price INTEGER,
            worker TEXT, created TEXT
        )
        """)

menu = ReplyKeyboardMarkup(
    [
        ["➕ Добавить автомобиль"],
        ["🔎 Найти автомобиль", "📊 Доход за сегодня"],
        ["🆔 Мой ID"]
    ],
    resize_keyboard=True
)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    name = update.effective_user.first_name
    await update.message.reply_text(
        f"Здравствуйте, {name}!\n"
        "Журнал 3D RAZVAL DEHQONOBOD",
        reply_markup=menu
    )

async def myid(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"Ваш Telegram ID: {update.effective_user.id}"
    )

async def add_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Введите номер автомобиля:")
    return PLATE

async def plate(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["plate"] = update.message.text.upper()
    await update.message.reply_text("Введите марку автомобиля:")
    return BRAND

async def brand(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["brand"] = update.message.text
    await update.message.reply_text("Введите пробег (км):")
    return MILEAGE

async def mileage(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["mileage"] = update.message.text
    await update.message.reply_text("Введите размер шин:")
    return TIRE

async def tire(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["tire"] = update.message.text
    await update.message.reply_text("Какую услугу выполнили?")
    return SERVICE

async def service(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data["service"] = update.message.text
    await update.message.reply_text("Введите стоимость услуги (сум):")
    return PRICE

async def price(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        amount = int(update.message.text.replace(" ", ""))
        if amount < 0:
            raise ValueError
    except ValueError:
        await update.message.reply_text("Введите стоимость числом, например 150000:")
        return PRICE

    u = update.effective_user
    with connect() as db:
        db.execute("""
        INSERT INTO cars
        (plate, brand, mileage, tire, service, price, worker, created)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            context.user_data["plate"],
            context.user_data["brand"],
            context.user_data["mileage"],
            context.user_data["tire"],
            context.user_data["service"],
            amount,
            u.full_name,
            datetime.now().strftime("%Y-%m-%d %H:%M")
        ))

    await update.message.reply_text(
        "✅ Автомобиль сохранён!\n"
        f"Номер: {context.user_data['plate']}\n"
        f"Марка: {context.user_data['brand']}\n"
        f"Пробег: {context.user_data['mileage']} км\n"
        f"Услуга: {context.user_data['service']}\n"
        f"Стоимость: {amount:,} сум",
        reply_markup=menu
    )
    return ConversationHandler.END

async def find_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Введите номер автомобиля для поиска:")
    return SEARCH

async def find_car(update: Update, context: ContextTypes.DEFAULT_TYPE):
    plate_number = update.message.text.upper().strip()
    with connect() as db:
        rows = db.execute(
            "SELECT plate, brand, mileage, tire, service, price, worker, created "
            "FROM cars WHERE plate = ? ORDER BY id DESC LIMIT 10",
            (plate_number,)
        ).fetchall()

    if not rows:
        await update.message.reply_text("Автомобиль не найден.", reply_markup=menu)
    else:
        result = "📋 История автомобиля:\n\n"
        for r in rows:
            result += (
                f"🚘 {r[0]} — {r[1]}\n"
                f"Пробег: {r[2]} км\n"
                f"Шины: {r[3]}\n"
                f"Услуга: {r[4]}\n"
                f"Цена: {r[5]:,} сум\n"
                f"Мастер: {r[6]}\n"
                f"Дата: {r[7]}\n\n"
            )
        await update.message.reply_text(result, reply_markup=menu)

    return ConversationHandler.END

async def today(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if ADMIN_ID == 0 or update.effective_user.id != ADMIN_ID:
        await update.message.reply_text("Эта функция доступна только администратору.")
        return

    date = datetime.now().strftime("%Y-%m-%d")
    with connect() as db:
        total, count = db.execute(
            "SELECT COALESCE(SUM(price), 0), COUNT(*) "
            "FROM cars WHERE created LIKE ?",
            (date + "%",)
        ).fetchone()

    await update.message.reply_text(
        f"📊 Доход за сегодня\n"
        f"Машин: {count}\n"
        f"Сумма: {total:,} сум"
    )

async def menu_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text
    if text == "➕ Добавить автомобиль":
        return await add_start(update, context)
    if text == "🔎 Найти автомобиль":
        return await find_start(update, context)
    if text == "📊 Доход за сегодня":
        return await today(update, context)
    if text == "🆔 Мой ID":
        return await myid(update, context)
    return ConversationHandler.END

def main():
    if not TOKEN:
        raise RuntimeError("BOT_TOKEN не указан в настройках сервера")

    init_db()
    app = Application.builder().token(TOKEN).build()

    add_conv = ConversationHandler(
        entry_points=[
            MessageHandler(filters.Regex("^➕ Добавить автомобиль$"), add_start)
        ],
        states={
            PLATE: [MessageHandler(filters.TEXT & ~filters.COMMAND, plate)],
            BRAND: [MessageHandler(filters.TEXT & ~filters.COMMAND, brand)],
            MILEAGE: [MessageHandler(filters.TEXT & ~filters.COMMAND, mileage)],
            TIRE: [MessageHandler(filters.TEXT & ~filters.COMMAND, tire)],
            SERVICE: [MessageHandler(filters.TEXT & ~filters.COMMAND, service)],
            PRICE: [MessageHandler(filters.TEXT & ~filters.COMMAND, price)],
        },
        fallbacks=[CommandHandler("cancel", start)],
    )

    find_conv = ConversationHandler(
        entry_points=[
            MessageHandler(filters.Regex("^🔎 Найти автомобиль$"), find_start)
        ],
        states={
            SEARCH: [MessageHandler(filters.TEXT & ~filters.COMMAND, find_car)]
        },
        fallbacks=[CommandHandler("cancel", start)],
    )

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("id", myid))
    app.add_handler(add_conv)
    app.add_handler(find_conv)
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, menu_handler))

    app.run_polling()

if __name__ == "__main__":
    main()
