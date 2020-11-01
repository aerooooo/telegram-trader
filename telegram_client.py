#Imports
import asyncio
import re
import sys
import time

import zmq
from telethon import TelegramClient, events

#Telegram Client Variables
name = 'anon'
api_id = '' #Fill this in
api_hash = '' #Fill this in
channel = '' #Fill this in


#ZMQ Server Variables
port = "5556"
topic = "Default"

#Telegram Client Initialization
client = TelegramClient(name, api_id, api_hash)

#ZMQ Server Initialization
context = zmq.Context()
publisher = context.socket(zmq.PUB)
publisher.bind("tcp://*:%s" % port)

#Data Structures
traded_symbols = ["AUDCAD","AUDCHF","AUDJPY","AUDNZD","AUDUSD","CADCHF","CADJPY",
                  "CHFJPY","EURAUD","EURCAD","EURCHF","EURGBP","EURJPY","EURNZD",
                  "EURUSD","GBPAUD","GBPCAD","GBPCHF","GBPJPY","GBPNZD","GBPUSD",
                  "NZDCAD","NZDCHF","NZDJPY","NZDUSD","USDCAD","USDCHF","USDJPY"]
traded_orders = ["BUY", "SELL"]

#Sync Funcs
#Print to stderr
def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

#Extract the price from a string
def extract_price(search_string):
    search_string = search_string.replace(". ", ".")
    search_string = search_string.replace(" .", ".") #Temp measure to handle Ronin typing errors
    try:
        return re.findall("\d*\.\d+", search_string)[0]
    except:
        eprint(''.join(["Error parsing search string: ", search_string]))
        return None

#Check if a given message entity is a signal, or just some other shit
def check_if_signal(message):
    if message.text is not None: #Ignore blank messages
        ascii_message = ''.join([i if ord(i) < 128 else ' ' for i in message.text])
    else:
        return None

    if ascii_message.count("\n") == 5: #Check for specific number of lines
        ascii_message_components = ascii_message.split("\n")
    else:
        return None

    symbol = ascii_message_components[0][0:6]
    entry = ascii_message_components[1]
    tp1 = ascii_message_components[2]
    tp2 = ascii_message_components[3]
    tp3 = ascii_message_components[4]
    sl = ascii_message_components[5] #Bruk down this signal into its components


    if not any(traded_symbol in symbol for traded_symbol in traded_symbols):
        return False #Only trade specific symbols

    if not any(order_type in entry for order_type in traded_orders):
        return False #Only trade BUY or SELL
    else:
        entry = extract_price(entry)

    if tp1[0:3] != "TP1": #Sanity check TP1
        return False
    else:
        tp1 = extract_price(tp1)

    if tp2[0:3] != "TP2": #Sanity check TP2
        return False
    else:
        tp2 = extract_price(tp2)

    if tp3[0:3] != "TP3": #Sanity check TP3
        return False
    else:
        tp3 = extract_price(tp3)

    if sl[0:2] != "SL": #Sanity check SL
        return False
    else:
        sl = extract_price(sl)

    return [symbol, entry, tp1, tp2, tp3, sl]


#Async Funcs
#On message to channel do
@client.on(events.NewMessage(chats=channel))
async def message_handler(event):
    is_signal = check_if_signal(event.message)
    if isinstance(is_signal, list):
        print(is_signal)
        try:
            publisher.send_string("%s %s" % (is_signal[0], str(is_signal)))
        except Exception as e:
            print(e)
    else:
        print("Not a parseable signal.")

#Main, just wait for async calls from message events
async def main():
    while True:
        await asyncio.sleep(1)

#Asyncio event loop
with client:
    client.loop.run_until_complete(main())


