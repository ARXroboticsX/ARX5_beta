from bimanual import SingleArm, Loading
from bimanual.ui import tick
from typing import Dict, Any
import traceback
import time


def test_remote_arm(master_left: SingleArm, master_right: SingleArm,
                    slave_left: SingleArm, slave_right: SingleArm):
    with Loading("左主臂回零"):
        master_left.go_home(1, wait=True)
    with Loading("右主臂回零"):
        master_right.go_home(1, wait=True)
    with Loading("左从臂回零"):
        slave_left.go_home(1, wait=True)
    with Loading("右从臂回零"):
        slave_right.go_home(1, wait=True)

    master_left.gravity_compensation()
    master_right.gravity_compensation()

    n = 0
    while True:

        left_pos = master_left.get_joint_positions()
        right_pos = master_right.get_joint_positions()

        slave_left.set_joint_positions(left_pos, duration=0)
        slave_right.set_joint_positions(right_pos, duration=0)


        for _name, _a in (("左主", master_left), ("右主", master_right),
                          ("左从", slave_left), ("右从", slave_right)):
            if _a.fault:
                print(f"\n🛑 {_name}臂安全保护: {_a.fault}\n程序退出。")
                raise SystemExit(1)

        tick(n, "运行中 (Ctrl+C 退出)"); n += 1

        time.sleep(0.01)          # ~100Hz 协调循环; 200Hz 下发在各自控制线程里


if __name__ == "__main__":

    # 0>2023  2>2025  3>A5
    master_left_config: Dict[str, Any] = {"can_port": "can2", "type": 2}
    master_right_config: Dict[str, Any] = {"can_port": "can4", "type": 2}
    slave_left_config: Dict[str, Any] = {"can_port": "can1", "type": 2}
    slave_right_config: Dict[str, Any] = {"can_port": "can3", "type": 2}

    _built = []
    try:
        for _cfg in (master_left_config, master_right_config,
                     slave_left_config, slave_right_config):
            with Loading(f"连接 {_cfg['can_port']} / 初始化"):
                _built.append(SingleArm(_cfg))
    except Exception:
        traceback.print_exc()                
        for _a in _built:
            try:
                _a.close()
            except Exception:
                pass

        raise SystemExit(1)
    master_left, master_right, slave_left, slave_right = _built
    try:
        test_remote_arm(master_left, master_right, slave_left, slave_right)
    except KeyboardInterrupt:
        print("\nCtrl+C -> 四臂复位并阻尼保护")
        for _a in _built:
            _a.go_home(1, wait=True)
        for _a in _built:
            _a.protect_mode()
        SingleArm.hold(1.0)       
    except SystemExit:

        for _a in _built:
            if _a.fault is None:
                _a.protect_mode()
        SingleArm.hold(1.0)
        raise
    finally:
        for _a in _built:
            try:
                _a.close()
            except Exception:
                pass
