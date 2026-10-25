from bimanual import EncoderArm, SingleArm, Loading
from bimanual.ui import tick
from typing import Dict, Any
import traceback
import time

# 1 3 左从 右从
# 2 4 左主 右主


GRIPPER_SCALE = 10
GRIPPER_OFFSET_LEFT =  -0.1
GRIPPER_OFFSET_RIGHT = -0.1


def gripper_to_slave_left(enc_rad: float) -> float:
    return GRIPPER_OFFSET_LEFT + abs(enc_rad * GRIPPER_SCALE)


def gripper_to_slave_right(enc_rad: float) -> float:
    return GRIPPER_OFFSET_RIGHT + abs(enc_rad * GRIPPER_SCALE)


def test_remote_encoder(master_left: EncoderArm, master_right: EncoderArm,
                        slave_left: SingleArm, slave_right: SingleArm):
    with Loading("左从臂回零"):
        slave_left.go_home(1, wait=True)
    with Loading("右从臂回零"):
        slave_right.go_home(1, wait=True)


    sides = (("左", master_left, slave_left, gripper_to_slave_left),
             ("右", master_right, slave_right, gripper_to_slave_right))
    n = 0
    while True:

        for _, master, slave, grip_map in sides:
            if not master.is_online:
                continue
            # 主臂 7 维 [J1..J6, 夹爪扳机原始角]; J1..J6 直接透传, 夹爪按侧映射
            pos = master.get_joint_positions()
            slave.set_joint_positions(pos[:6], duration=0)
            slave.set_gripper_pos(grip_map(pos[6]))


        for name, _, slave, _ in sides:
            if slave.fault:
                print(f"\n🛑 {name}从臂安全保护: {slave.fault}\n程序退出。")
                raise SystemExit(1)

        off = [name for name, master, *_ in sides if not master.is_online]
        tick(n, f"⚠ {'/'.join(off)}主臂离线, 该侧从臂保持原位 (上电自动恢复)"
                if off else "运行中 (Ctrl+C 退出)")
        n += 1

        time.sleep(0.01)          # ~100Hz 协调循环; 200Hz 下发在从臂控制线程里


if __name__ == "__main__":

    # :主臂=编码器 can2/can4, 从臂=电机臂 can1/can3
    master_left_config: Dict[str, Any] = {"can_port": "can2"}
    master_right_config: Dict[str, Any] = {"can_port": "can4"}
    # 0>2023  2>2025  3>A5
    slave_left_config: Dict[str, Any] = {"can_port": "can1", "type": 0}
    slave_right_config: Dict[str, Any] = {"can_port": "can3", "type": 0}

    _built = []
    try:
        for _cfg in (master_left_config, master_right_config):
            with Loading(f"连接编码器示教臂 {_cfg['can_port']}"):
                _built.append(EncoderArm(_cfg))
        for _cfg in (slave_left_config, slave_right_config):
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
        test_remote_encoder(master_left, master_right, slave_left, slave_right)
    except KeyboardInterrupt:
        print("\nCtrl+C -> 从臂复位并阻尼保护")
        for _a in (slave_left, slave_right):
            _a.go_home(1, wait=True)
        for _a in (slave_left, slave_right):
            _a.protect_mode()
        SingleArm.hold(1.0)       
    except SystemExit:
        for _a in (slave_left, slave_right):
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
