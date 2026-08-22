export type TradeDirection = "BUY" | "SELL" | "HOLD";
export type SubscriptionTier = "core" | "precision" | "sovereign";

export interface AIVote {
  modelName: string;
  direction: TradeDirection;
  confidence: number;
  reasoning: string;
}

export interface SwarmConsensus {
  symbol: string;
  finalDirection: TradeDirection;
  consensusPercentage: number;
  votes: AIVote[];
  timestamp: string;
  requiredThreshold: number;
  approved: boolean;
}

export interface RiskLimits {
  maxDailyDrawdownPct: number;
  riskPerTradePct: number;
  autoBreakevenAtR: number;
  autoBank50AtR: number;
}
