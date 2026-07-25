# Mehd AI -- Broker Scanner
import logging
from datetime import datetime, timezone, timedelta
from storage import storage
from models import get_pip_size

logger = logging.getLogger('mehd.broker_scanner')

SLIPPAGE_THRESHOLD_PIPS = 1.5
LATENCY_THRESHOLD_MS    = 200

DEMO_HEALTH_SCORES = {
    'pepperstone': {'health_score': 96,'avg_latency_ms': 45,'avg_slippage_pips': 0.2,'incident_count': 3,'trust_tier': 'ECN','warning': '','last_updated': 'demo'},
    'icmarkets':   {'health_score': 94,'avg_latency_ms': 40,'avg_slippage_pips': 0.3,'incident_count': 5,'trust_tier': 'ECN','warning': '','last_updated': 'demo'},
    'oanda':       {'health_score': 88,'avg_latency_ms': 60,'avg_slippage_pips': 0.6,'incident_count': 12,'trust_tier': 'Hybrid','warning': 'OANDA occasionally widens spreads during high-impact news events.','last_updated': 'demo'},
    'xm':          {'health_score': 72,'avg_latency_ms': 120,'avg_slippage_pips': 1.4,'incident_count': 58,'trust_tier': 'Hybrid','warning': 'Significant execution delays recorded during US session.','last_updated': 'demo'},
    'exness':      {'health_score': 42,'avg_latency_ms': 350,'avg_slippage_pips': 3.5,'incident_count': 220,'trust_tier': 'Market Maker','warning': 'HIGH RISK: Community data shows frequent spread manipulation and execution delays. Consider switching to a verified ECN broker.','last_updated': 'demo'},
}


def get_demo_health() -> dict:
    """
    Returns the demo health scores for use in DEMO_MODE.
    Called by main.py GET /broker_health when DEMO_MODE=True.
    This gives the Flutter client realistic-looking data during sandbox testing.
    """
    return {'brokers': DEMO_HEALTH_SCORES, 'last_updated': 'demo', 'is_demo': True}



async def log_execution_performance(broker_id, symbol, direction, trigger_price, fill_price, trigger_time, fill_time):
    if not broker_id or broker_id in ('unknown', 'demo'):
        return
    pip_size = get_pip_size(symbol)
    if not pip_size or pip_size <= 0:
        return
    latency_ms = max(0, int((fill_time - trigger_time).total_seconds() * 1000))
    raw_diff = fill_price - trigger_price
    adverse_movement = -raw_diff if direction.upper() == 'BUY' else raw_diff
    slippage_pips = round(max(0.0, adverse_movement / pip_size), 2)
    is_latency_incident  = latency_ms    > LATENCY_THRESHOLD_MS
    is_slippage_incident = slippage_pips > SLIPPAGE_THRESHOLD_PIPS
    if not is_latency_incident and not is_slippage_incident:
        return
    incident_type = ('BOTH' if is_latency_incident and is_slippage_incident else 'LATENCY' if is_latency_incident else 'SLIPPAGE')
    incident_key  = broker_id + '_' + fill_time.strftime('%Y%m%d_%H%M%S_%f')
    incident_data = {'broker_id': broker_id.lower(),'symbol': symbol,'direction': direction.upper(),'latency_ms': latency_ms,'slippage_pips': slippage_pips,'incident_type': incident_type,'timestamp': fill_time.isoformat()}
    try:
        await storage.set('broker_incidents', incident_key, incident_data)
        logger.warning('Broker incident [%s] | %s | %s | Slippage: %.2f pips | Latency: %dms', incident_type, broker_id.upper(), symbol, slippage_pips, latency_ms)
    except Exception as e:
        logger.error('Broker Scanner: Failed to log incident: %s', e)


async def aggregate_broker_health():
    try:
        cutoff    = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
        incidents = await storage.query('broker_incidents', [('timestamp', '>=', cutoff)])
        if not incidents:
            logger.info('Broker Scanner: No incidents in the last 30 days.')
            return
        broker_stats = {}
        for inc in incidents.values():
            bid = inc.get('broker_id', 'unknown')
            if bid == 'unknown':
                continue
            if bid not in broker_stats:
                broker_stats[bid] = {'latencies': [], 'slippages': [], 'count': 0}
            broker_stats[bid]['latencies'].append(inc.get('latency_ms', 0))
            broker_stats[bid]['slippages'].append(inc.get('slippage_pips', 0.0))
            broker_stats[bid]['count'] += 1
        health_summary = {}
        for broker_id, stats in broker_stats.items():
            avg_latency    = round(sum(stats['latencies']) / len(stats['latencies']))
            avg_slippage   = round(sum(stats['slippages']) / len(stats['slippages']), 2)
            incident_count = stats['count']
            health  = 100.0
            health -= min(40.0, avg_latency / 10)
            health -= min(40.0, avg_slippage * 15)
            health -= min(20.0, incident_count * 0.05)
            health  = max(0, round(health))
            if health >= 90:
                trust_tier = 'ECN'
                warning    = ''
            elif health >= 75:
                trust_tier = 'Hybrid'
                warning    = 'Some execution delays recorded (avg ' + str(avg_latency) + 'ms). Monitor closely.'
            else:
                trust_tier = 'Market Maker'
                warning    = 'HIGH RISK: Community data shows frequent execution issues. Avg slippage: ' + str(avg_slippage) + ' pips, Avg delay: ' + str(avg_latency) + 'ms. Consider switching to a verified ECN broker.'
            health_summary[broker_id] = {'health_score': health,'avg_latency_ms': avg_latency,'avg_slippage_pips': avg_slippage,'incident_count': incident_count,'trust_tier': trust_tier,'warning': warning,'last_updated': datetime.now(timezone.utc).isoformat()}
            logger.info('Broker health | %s | %d/100 | Latency: %dms | Slippage: %.2f pips | Incidents: %d', broker_id.upper(), health, avg_latency, avg_slippage, incident_count)
        await storage.set('system_metrics', 'broker_health', {'brokers': health_summary, 'last_updated': datetime.now(timezone.utc).isoformat()})
        logger.info('Broker Scanner: Health scores published for %d broker(s).', len(health_summary))
    except Exception as e:
        logger.error('Broker Scanner: Aggregation failed: %s', e)
