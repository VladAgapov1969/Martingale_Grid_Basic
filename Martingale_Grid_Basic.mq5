//+------------------------------------------------------------------+
//|  Minimal Grid Martingale EA — MQL5, entries at Open[0]          |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>

input double First_lot        = 0.01;
input double Distance_in_pips = 55;
input int    Max_Orders       = 10;
input double TP_in_money      = 0.50;
input double Lot_Multiplier   = 2.0;
input ulong  MagicNumber      = 345345;
input string OrderComment     = "Razrulifatele.Portfolio";

CTrade   trade;
double   g_point;
int      g_lotdig;
datetime g_lastBar = 0;

//+------------------------------------------------------------------+
int OnInit() {
   g_point = (Digits() == 3 || Digits() == 5) ? 10.0 * _Point : _Point;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_lotdig = (step >= 0.01) ? 2 : (step >= 0.1 ? 1 : 2);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(3);
   trade.SetTypeFillingBySymbol(_Symbol);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
void OnTick() {

   //=== new-bar gate ==============================================
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (barTime == g_lastBar) return;
   g_lastBar = barTime;

   //=== 1. scan basket ============================================
   int      buys = 0, sells = 0;
   long     firstType  = -1;
   datetime firstTime  = 0;
   datetime newestTime = 0;
   double   lastLots   = 0;
   double   lastPrice  = 0;
   double   basketProfit = 0;

   int n = PositionsTotal();
   for (int i = 0; i < n; i++) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      long     ptype  = PositionGetInteger(POSITION_TYPE);
      datetime opt    = (datetime)PositionGetInteger(POSITION_TIME);
      double   lots   = PositionGetDouble(POSITION_VOLUME);
      double   openp  = PositionGetDouble(POSITION_PRICE_OPEN);
      double   profit = PositionGetDouble(POSITION_PROFIT)
                      + PositionGetDouble(POSITION_SWAP);

      if (ptype == POSITION_TYPE_BUY)  buys++;
      if (ptype == POSITION_TYPE_SELL) sells++;

      if (firstType == -1 || opt < firstTime) {
         firstTime = opt;
         firstType = ptype;
      }
      if (opt > newestTime) {
         newestTime = opt;
         lastLots   = lots;
         lastPrice  = openp;
      }

      basketProfit += profit;
   }
   int total = buys + sells;

   //=== 2. EXIT: basket money target ==============================
   if (total > 0 && basketProfit >= TP_in_money) {
      CloseAll();
      return;
   }

   //=== 3. ENTRY: first position at bar open ======================
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 2);
   double currClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (total == 0) {
      double lot = NormalizeDouble(First_lot, g_lotdig);
      if (prevClose < currClose) {
         if (AccountFreeMarginCheck(_Symbol, ORDER_TYPE_BUY, lot) > 0)
            trade.Buy(lot, _Symbol, ask, 0, 0, OrderComment);
      }
      else if (prevClose > currClose) {
         if (AccountFreeMarginCheck(_Symbol, ORDER_TYPE_SELL, lot) > 0)
            trade.Sell(lot, _Symbol, bid, 0, 0, OrderComment);
      }
      return;
   }

   //=== 4. GRID ADD: counter-trend, martingale x2 =================
   if (total >= Max_Orders) return;

   double step     = Distance_in_pips * g_point;
   double nextLot  = NormalizeDouble(lastLots * Lot_Multiplier, g_lotdig);
   double refPrice = iOpen(_Symbol, PERIOD_CURRENT, 0);

   if (firstType == POSITION_TYPE_BUY && sells == 0) {
      if (refPrice <= lastPrice - step) {
         if (AccountFreeMarginCheck(_Symbol, ORDER_TYPE_BUY, nextLot) > 0)
            trade.Buy(nextLot, _Symbol, ask, 0, 0, OrderComment);
      }
   }
   else if (firstType == POSITION_TYPE_SELL && buys == 0) {
      if (refPrice >= lastPrice + step) {
         if (AccountFreeMarginCheck(_Symbol, ORDER_TYPE_SELL, nextLot) > 0)
            trade.Sell(nextLot, _Symbol, bid, 0, 0, OrderComment);
      }
   }
}

//+------------------------------------------------------------------+
void CloseAll() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      trade.PositionClose(ticket);
   }
}