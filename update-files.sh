#!/bin/bash

set -e

echo "🔧 Переход в папку rl-swarm"
cd rl-swarm || { echo "❌ Папка rl-swarm не найдена"; exit 1; }

echo "🧹 Очистка initial_peers в configs/rg-swarm.yaml"
awk '
/^  initial_peers:/ {
    print "  initial_peers: []"
    skip=1
    next
}
/^  [^[:space:]]/ && skip {
    skip=0
}
skip && /^    - / {
    next
}
{ print }
' ./configs/rg-swarm.yaml > ./configs/rg-swarm.yaml.tmp && mv ./configs/rg-swarm.yaml.tmp ./configs/rg-swarm.yaml

echo "🧹 Очистка initial_peers в rgym_exp/config/rg-swarm.yaml"
awk '
/^  initial_peers:/ {
    print "  initial_peers: []"
    skip=1
    next
}
/^  [^[:space:]]/ && skip {
    skip=0
}
skip && /^    - / {
    next
}
{ print }
' ./rgym_exp/config/rg-swarm.yaml > ./rgym_exp/config/rg-swarm.yaml.tmp && mv ./rgym_exp/config/rg-swarm.yaml.tmp ./rgym_exp/config/rg-swarm.yaml

HIVEMIND_BACKEND=$(find .venv/lib/ -type f -path "*/site-packages/genrl/communication/hivemind/hivemind_backend.py" | head -n 1) 

if [[ -z "$HIVEMIND_BACKEND" ]]; then
  echo "❌ Не удалось найти hivemind_backend.py"
  exit 1
fi


echo "📝 Замена содержимого $HIVEMIND_BACKEND"

cat > "$HIVEMIND_BACKEND" <<'EOF'
import os
import pickle
import time
import logging
from typing import Any, Dict, List, Optional

import torch.distributed as dist
from hivemind import DHT, get_dht_time

from genrl.communication.communication import Communication
from genrl.serialization.game_tree import from_bytes, to_bytes

logger = logging.getLogger(__name__)

class HivemindRendezvouz:
    _STORE = None
    _IS_MASTER = False
    _IS_LAMBDA = False
    _initial_peers: List[str] = [
        # Можно добавить сюда дефолтных бустрэп пиров, если хочешь
        # "/ip4/38.101.215.15/tcp/30011/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ",
        # "/ip4/38.101.215.15/tcp/30012/p2p/QmWhiaLrx3HRZfgXc2i7KW5nMUNK7P9tRc71yFJdGEZKkC",
        # "/ip4/38.101.215.15/tcp/30013/p2p/QmQa1SCfYTxx7RvU7qJJRo79Zm1RAwPpkeLueDVJuBBmFp"
    ]

    @classmethod
    def init(cls, is_master: bool = False):
        cls._IS_MASTER = is_master
        cls._IS_LAMBDA = os.environ.get("LAMBDA", False)
        if cls._STORE is None and cls._IS_LAMBDA:
            world_size = int(os.environ.get("HIVEMIND_WORLD_SIZE", 1))
            cls._STORE = dist.TCPStore(
                host_name=os.environ["MASTER_ADDR"],
                port=int(os.environ["MASTER_PORT"]),
                is_master=is_master,
                world_size=world_size,
                wait_for_workers=True,
            )

    @classmethod
    def is_bootstrap(cls) -> bool:
        return cls._IS_MASTER

    @classmethod
    def set_initial_peers(cls, initial_peers: List[str]):
        if cls._STORE is None and cls._IS_LAMBDA:
            cls.init()
        if cls._IS_LAMBDA and cls._STORE is not None:
            cls._STORE.set("initial_peers", pickle.dumps(initial_peers))

    @classmethod
    def get_initial_peers(cls) -> List[str]:
        # Если хочешь отключить lookup из цепочки (например, для локального запуска)
        if not getattr(cls, 'force_chain_lookup', True):
            logger.info("force_chain_lookup=False, returning empty initial peers list")
            return []

        # Фильтрация "мертвых" пиров по IP 38.101.215.15
        dead_ip_prefix = "/ip4/38.101.215.15"

        # Получаем пиров из store, если в режиме lambda, иначе из _initial_peers
        if cls._STORE is not None and cls._IS_LAMBDA:
            cls._STORE.wait(["initial_peers"])
            peer_bytes = cls._STORE.get("initial_peers")
            if peer_bytes is not None:
                peers = pickle.loads(peer_bytes)
            else:
                peers = []
        else:
            peers = cls._initial_peers

        alive_peers = [p for p in peers if not p.startswith(dead_ip_prefix)]

        if alive_peers:
            logger.info(f"Returning alive initial peers: {alive_peers}")
            return alive_peers
        else:
            logger.warning("No alive initial peers found, returning empty list")
            return []

class HivemindBackend(Communication):
    def __init__(
        self,
        initial_peers: Optional[List[str]] = None,
        timeout: int = 600,
        disable_caching: bool = False,
        beam_size: int = 1000,
        **kwargs,
    ):
        self.world_size = int(os.environ.get("HIVEMIND_WORLD_SIZE", 1))
        self.timeout = timeout
        self.bootstrap = HivemindRendezvouz.is_bootstrap()
        self.beam_size = beam_size
        self.dht = None

        if disable_caching:
            kwargs['cache_locally'] = False
            kwargs['cache_on_store'] = False

        # Если initial_peers не передан, берем из HivemindRendezvouz с фильтрацией
        if initial_peers is None:
            initial_peers = HivemindRendezvouz.get_initial_peers()

        if self.bootstrap:
            # Bootstrap нода — запускает DHT с заданными initial_peers (можно пустой список)
            self.dht = DHT(
                start=True,
                host_maddrs=["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic"],
                initial_peers=initial_peers,
                **kwargs,
            )
            dht_maddrs = self.dht.get_visible_maddrs(latest=True)
            HivemindRendezvouz.set_initial_peers(dht_maddrs)
            logger.info(f"Bootstrap DHT started, visible maddrs: {dht_maddrs}")
        else:
            # Участник сети — подключается к bootstrap пирами
            self.dht = DHT(
                start=True,
                host_maddrs=["/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic"],
                initial_peers=initial_peers,
                **kwargs,
            )
            logger.info(f"Non-bootstrap DHT started, connected to peers: {initial_peers}")

        self.step_ = 0

    def all_gather_object(self, obj: Any) -> Dict[str | int, Any]:
        key = str(self.step_)
        try:
            _ = self.dht.get_visible_maddrs(latest=True)
            obj_bytes = to_bytes(obj)
            self.dht.store(
                key,
                subkey=str(self.dht.peer_id),
                value=obj_bytes,
                expiration_time=get_dht_time() + self.timeout,
                beam_size=self.beam_size,
            )

            time.sleep(1)
            t_ = time.monotonic()
            while True:
                output_, _ = self.dht.get(key, beam_size=self.beam_size, latest=True)
                if len(output_) >= self.world_size:
                    break
                else:
                    if time.monotonic() - t_ > self.timeout:
                        raise RuntimeError(
                            f"Failed to obtain {self.world_size} values for {key} within timeout."
                        )
            self.step_ += 1

            tmp = sorted(
                [(key, from_bytes(value.value)) for key, value in output_.items()],
                key=lambda x: x[0],
            )
            return {key: value for key, value in tmp}
        except (BlockingIOError, EOFError) as e:
            logger.error(f"all_gather_object error: {e}")
            return {str(self.dht.peer_id): obj}

    def get_id(self):
        return str(self.dht.peer_id)
EOF

echo "✅ Скрипт завершён. Все изменения применены."
