from bimanual import SingleArm, Loading
from bimanual.ui import tick
from typing import Dict, Any
import traceback
import time


def test_dual_arm(left_arm: SingleArm, right_arm: SingleArm):
    with Loading("左臂回零"):
        left_arm.go_home(1, wait=True)
    with Loading("右臂回零"):
        right_arm.go_home(1, wait=True)

    n = 0
    while True:

        # left_arm.gravity_compensation()
        # right_arm.gravity_compensation()

        positions = [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]  # 指定每个关节的位置
        joint_names = ["joint1", "joint2", "joint3","joint4", "joint5", "joint6"]  # 对应关节的名称
        left_arm.set_joint_positions(positions=positions,duration=0)
        left_arm.set_gripper_pos(-1)
        right_arm.set_joint_positions(positions=positions,duration=0)
        right_arm.set_gripper_pos(-1)




        tick(n, "运行中 (Ctrl+C 退出)"); n += 1

        time.sleep(0.01)          # ~100Hz 协调循环; 200Hz 下发在各自控制线程里


if __name__ == "__main__":

    left_arm_config: Dict[str, Any] = {
        "can_port": "can1",
        "type": 2,           # 0>2023  2>2025  3>A5
        # "urdf_path": "left.urdf",     # 可选: 每臂各自 URDF, 相对 bimanual/models/ (末端质量不同时)
    }
    right_arm_config: Dict[str, Any] = {
        "can_port": "can3",
        "type": 2,
        # "urdf_path": "right.urdf",
    }


    _built = []
    try:
        for _cfg in (left_arm_config, right_arm_config):
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
    left_arm, right_arm = _built
    try:
        test_dual_arm(left_arm, right_arm)
    except KeyboardInterrupt:
        print("\nCtrl+C -> 双臂复位并阻尼保护")
        left_arm.go_home(0.5, wait=True)
        right_arm.go_home(0.5, wait=True)
        left_arm.protect_mode()
        right_arm.protect_mode()
        SingleArm.hold(1.0)
    finally:
        for _a in (left_arm, right_arm):
            try:
                _a.close()
            except Exception:
                pass
