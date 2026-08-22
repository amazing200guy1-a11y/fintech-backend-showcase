package com.mehd.quant;

import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Institutional FIX 4.4 Protocol Engine for Tier-1 Liquidity Providers (LMAX / Currenex / Integral).
 */
public class FixProtocolAdapter {

    private final String senderCompId;
    private final String targetCompId;
    private final AtomicLong seqNum = new AtomicLong(1);
    private final ConcurrentHashMap<String, String> activeOrders = new ConcurrentHashMap<>();

    public FixProtocolAdapter(String senderCompId, String targetCompId) {
        this.senderCompId = senderCompId;
        this.targetCompId = targetCompId;
    }

    /**
     * Constructs a Tag-Value encoded NewOrderSingle (MsgType=D) with strict Fill-Or-Kill (TimeInForce=4).
     */
    public String buildNewOrderSingle(
            String clOrdId,
            String symbol,
            char side, // '1' = Buy, '2' = Sell
            double price,
            double quantity,
            double maxSlippagePips
    ) {
        StringBuilder fixMsg = new StringBuilder();
        String timestamp = Instant.now().toString();

        // Standard Header
        fixMsg.append("8=FIX.4.4\u0001");
        fixMsg.append("35=D\u0001"); // MsgType: NewOrderSingle
        fixMsg.append("49=").append(senderCompId).append("\u0001");
        fixMsg.append("56=").append(targetCompId).append("\u0001");
        fixMsg.append("34=").append(seqNum.getAndIncrement()).append("\u0001");
        fixMsg.append("52=").append(timestamp).append("\u0001");

        // Order Parameters
        fixMsg.append("11=").append(clOrdId).append("\u0001"); // ClOrdID
        fixMsg.append("55=").append(symbol).append("\u0001");  // Symbol
        fixMsg.append("54=").append(side).append("\u0001");    // Side
        fixMsg.append("40=2\u0001");                          // OrdType: Limit
        fixMsg.append("44=").append(String.format("%.5f", price)).append("\u0001"); // Price
        fixMsg.append("38=").append(String.format("%.2f", quantity)).append("\u0001"); // OrderQty
        fixMsg.append("59=4\u0001");                          // TimeInForce: 4 = Fill-Or-Kill (FOK)

        activeOrders.put(clOrdId, symbol);
        return fixMsg.toString();
    }

    /**
     * Parses ExecutionReport (MsgType=8) messages from Tier-1 Liquidity Providers.
     */
    public boolean parseExecutionReport(String fixRawMessage) {
        if (fixRawMessage == null || !fixRawMessage.contains("35=8")) {
            return false;
        }
        return fixRawMessage.contains("39=2"); // 39=2 -> OrdStatus: Filled
    }
}
