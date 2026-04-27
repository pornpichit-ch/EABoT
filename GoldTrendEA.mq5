//+------------------------------------------------------------------+
//|                                              GoldTrendEA.mq5     |
//|                          XAU/USD Day Trading with BB + RSI       |
//|                                    Created 2026                  |
//+------------------------------------------------------------------+
#property copyright "GoldTrendEA"
#property link      "https://github.com/pornpichit-ch/EABoT"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input double LotSize       = 0.01;  // Lot size per order
input int    MaxOpenTrades = 3;     // Maximum open trades
input int    StopLoss      = 50;    // Stop Loss in pips
input int    TakeProfit    = 50;    // Take Profit in pips

// Bollinger Bands settings
input int    BBPeriod    = 20;   // Bollinger Bands period
input double BBDeviation = 2.0;  // Bollinger Bands deviation

// RSI settings
input int    RSIPeriod     = 14;  // RSI period
input double RSIOverbought = 70;  // RSI Overbought level
input double RSIOversold   = 30;  // RSI Oversold level

//--- Global variables
int    g_bbHandle  = INVALID_HANDLE;
int    g_rsiHandle = INVALID_HANDLE;
string g_eaComment = "GoldTrendEA";
CTrade g_trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Create indicator handles
    g_bbHandle = iBands(_Symbol, PERIOD_CURRENT, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
    if (g_bbHandle == INVALID_HANDLE)
    {
        Print("Error creating Bollinger Bands handle: ", GetLastError());
        return INIT_FAILED;
    }

    g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
    if (g_rsiHandle == INVALID_HANDLE)
    {
        Print("Error creating RSI handle: ", GetLastError());
        return INIT_FAILED;
    }

    g_trade.SetExpertMagicNumber(12345);

    Print("===== GoldTrendEA Initialized =====");
    Print("Symbol: ",        _Symbol);
    Print("Lot Size: ",      LotSize);
    Print("Max Trades: ",    MaxOpenTrades);
    Print("Stop Loss: ",     StopLoss,      " pips");
    Print("Take Profit: ",   TakeProfit,    " pips");
    Print("BB Period: ",     BBPeriod,      " | Deviation: ", BBDeviation);
    Print("RSI Period: ",    RSIPeriod,     " | Overbought: ", RSIOverbought, " | Oversold: ", RSIOversold);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if (g_bbHandle  != INVALID_HANDLE) IndicatorRelease(g_bbHandle);
    if (g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);

    Print("===== GoldTrendEA Deinitialized ===== Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Only trade on new bar to avoid multiple signals per candle
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (currentBarTime == lastBarTime)
        return;
    lastBarTime = currentBarTime;

    // Check if we can open new trades
    if (CountOpenTrades() >= MaxOpenTrades)
        return;

    // Get indicator buffers (index 1 = previous closed bar)
    double upperBand[1], middleBand[1], lowerBand[1], rsiValue[1];

    if (CopyBuffer(g_bbHandle, 0, 1, 1, middleBand) < 1) return;  // 0 = Middle Band
    if (CopyBuffer(g_bbHandle, 1, 1, 1, upperBand)  < 1) return;  // 1 = Upper Band
    if (CopyBuffer(g_bbHandle, 2, 1, 1, lowerBand)  < 1) return;  // 2 = Lower Band
    if (CopyBuffer(g_rsiHandle, 0,           1, 1, rsiValue)   < 1) return;

    double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);

    // Buy Signal: Price touches lower BB AND RSI is oversold
    if (closePrice <= lowerBand[0] && rsiValue[0] < RSIOversold)
    {
        if (CountOrdersByType(ORDER_TYPE_BUY) < 1)
            OpenBuyOrder();
    }

    // Sell Signal: Price touches upper BB AND RSI is overbought
    if (closePrice >= upperBand[0] && rsiValue[0] > RSIOverbought)
    {
        if (CountOrdersByType(ORDER_TYPE_SELL) < 1)
            OpenSellOrder();
    }
}

//+------------------------------------------------------------------+
//| Count all open trades for this EA                                |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;

        if (PositionGetString(POSITION_SYMBOL)  == _Symbol &&
            PositionGetInteger(POSITION_MAGIC)  == 12345)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Count open orders by type (BUY or SELL)                          |
//+------------------------------------------------------------------+
int CountOrdersByType(ENUM_ORDER_TYPE orderType)
{
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;

        if (PositionGetString(POSITION_SYMBOL)         == _Symbol   &&
            PositionGetInteger(POSITION_MAGIC)         == 12345     &&
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == (ENUM_POSITION_TYPE)orderType)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                   |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
    double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double sl     = ask - StopLoss  * point;
    double tp     = ask + TakeProfit * point;

    if (!g_trade.Buy(LotSize, _Symbol, ask, sl, tp, g_eaComment))
    {
        Print("Error opening BUY order: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
    }
    else
    {
        Print("BUY Order opened | Price=", ask, " | SL=", sl, " | TP=", tp);
    }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                  |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
    double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double sl     = bid + StopLoss   * point;
    double tp     = bid - TakeProfit * point;

    if (!g_trade.Sell(LotSize, _Symbol, bid, sl, tp, g_eaComment))
    {
        Print("Error opening SELL order: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
    }
    else
    {
        Print("SELL Order opened | Price=", bid, " | SL=", sl, " | TP=", tp);
    }
}

//+------------------------------------------------------------------+
//| End of Expert Advisor                                            |
//+------------------------------------------------------------------+
