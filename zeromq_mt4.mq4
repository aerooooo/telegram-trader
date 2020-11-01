//+------------------------------------------------------------------+
//|                                                  zeromq_test.mq4 |
//|                                     Copyright 2020, Max Sargent. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Properties & Includes                                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, Max Sargent."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#include <Zmq/Zmq.mqh>

//+------------------------------------------------------------------+
//| ZMQ Variables                                                    |
//+------------------------------------------------------------------+
Context context();
Socket subscriber(context,ZMQ_SUB);
ZmqMsg signal;
PollItem items[1];

//+------------------------------------------------------------------+
//| Trading Variables                                                |
//+------------------------------------------------------------------+
int tradeOpCode; //0 is BUY 1 is SELL
double SL;
double TP1;
double TP2;
double TP3;
double Risk = 1; //Risk in %

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   subscriber.connect("tcp://localhost:5556");  
   subscriber.subscribe(Symbol());
   subscriber.fillPollItem(items[0],ZMQ_POLLIN);
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
   Print("Deinitialization with exit code: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   Socket::poll(items,0);
   if(items[0].hasInput()){
      subscriber.recv(signal);
      if(CheckFreeMargin()){
         ParseSignal(signal.getData());
         ExecuteSignal();
      }else{
         Print("Cant execute trade, not enough margin for safe buffer!");
      }
   }
   CheckOpenPositions();
  }

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
void ParseSignal(string signalString){
   string splitSignal[];
   ushort seperator;
   
   seperator = StringGetCharacter(",", 0);
   
   StringReplace(signalString, "[", "");
   StringReplace(signalString, "]", "");
   StringReplace(signalString, "'", "");
   StringSplit(signalString, seperator, splitSignal);
   
   //Print(splitSignal[0]); Symbol
   //Print(splitSignal[1]); Entry
   TP1 = StrToDouble(splitSignal[2]);
   TP2 = StrToDouble(splitSignal[3]);
   TP3 = StrToDouble(splitSignal[4]);
   SL = StrToDouble(splitSignal[5]);
   
   TP1 = TP1 - (20 * Point());
   TP2 = TP2 - (20 * Point());
   TP3 = TP3 - (20 * Point()); //Stop us just missing TPs by 1 or 2 pips
   
   if(SL < TP1) tradeOpCode = 0;
   if(SL > TP1) tradeOpCode = 1;
   
}

void ExecuteSignal(){
   int returnCode;
   double lotSize = ND(GetLotSize());
   if(tradeOpCode == 0){
      returnCode = OrderSend(Symbol(), tradeOpCode, lotSize * 0.4, Ask, 2, SL, TP1, "TP1");
      if(returnCode == -1) Print(GetLastError());
      returnCode = OrderSend(Symbol(), tradeOpCode, lotSize * 0.6, Ask, 2, SL, TP2, "TP2");
      if(returnCode == -1) Print(GetLastError());
//      returnCode = OrderSend(Symbol(), tradeOpCode, lotSize * 0.2, Ask, 2, SL, TP3, "TP3");
//      if(returnCode == -1) Print(GetLastError());
   }else if(tradeOpCode == 1){
      returnCode = OrderSend(Symbol(), tradeOpCode, lotSize * 0.4, Bid, 2, SL, TP1, "TP1");
      if(returnCode == -1) Print(GetLastError());
      returnCode = OrderSend(Symbol(), tradeOpCode, lotSize * 0.6, Bid, 2, SL, TP2, "TP2");
      if(returnCode == -1) Print(GetLastError());
//      returnCode = OrderSend(Symbol(), tradeOpCode, lotSize * 0.2, Bid, 2, SL, TP3, "TP3");
//      if(returnCode == -1) Print(GetLastError());
   }
   
}

double ND(double val){
   return(NormalizeDouble(val, Digits));
}

void CheckOpenPositions(){
   int i = 0;
   bool returnCode;
   string comment = "";
   double pipsProfit = 0.0;
   
   for(i; i < OrdersTotal(); i++){
      
      returnCode = OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if(returnCode == false) Print(GetLastError());
      
      if(OrderType() == OP_BUY) pipsProfit = ND(MarketInfo(OrderSymbol(), MODE_BID) - OrderOpenPrice())/Point/1;
      if(OrderType() == OP_SELL) pipsProfit = ND(OrderOpenPrice() - MarketInfo(OrderSymbol(),MODE_ASK))/Point/1;
      
      
      if(OrderSymbol() == Symbol()){
         comment = OrderComment();
         if(comment == "TP1"){ // Do nothing, TP1 just takes 20 pips
            break;
         }
         if(comment == "TP2"){ // If we are 20 pips in profit, then SL to BE
            if(pipsProfit >= 200 && OrderStopLoss() != OrderOpenPrice()){
               returnCode = OrderModify(OrderTicket(),OrderOpenPrice(),OrderOpenPrice(),OrderTakeProfit(),0);
               if(returnCode == false) Print(GetLastError());
               break;
            }
         }
         if(comment == "TP3"){ // Trail the stop on TP3 for maximum profit
            if(pipsProfit >= 200 && OrderStopLoss() != OrderOpenPrice()){
               returnCode = OrderModify(OrderTicket(),OrderOpenPrice(),OrderOpenPrice(),OrderTakeProfit(),0);
               if(returnCode == false) Print(GetLastError());
               break;
            }
         }
      }
   }
}

double GetLotSize(){
   double tradeVolume = AccountFreeMargin() * Risk / 100 / ( 400 * MarketInfo( Symbol(), MODE_TICKVALUE ) );
   return tradeVolume;
}

bool CheckFreeMargin(){
   return (AccountFreeMargin() > AccountBalance() * 0.25);
}