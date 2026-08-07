from bimanual import SingleArm, Loading
from bimanual.ui import tick
from typing import Dict, Any
import numpy as np
import sys
import time

def test_single_arm(single_arm: SingleArm, duration: float = 10.0, dt: float = 0.01):

    with Loading("回零"):
        single_arm.go_home(1, wait=True)

    n = 0
    while(1):

        # single_arm.gravity_compensation()

        # xyzrpy = np.array([0.0, 0.0, 0.1,0.0, 0.0, 0.0])  # x, y, z 位置
        # single_arm.set_ee_pose_xyzrpy(xyzrpy,duration=0)
        # single_arm.set_gripper_pos(-3)

        # positions = [0.2, 0.2, -0.2, 0.2, 0.2, 0.2]  # 指定每个关节的位置
        # joint_names = ["joint1", "joint2", "joint3","joint4", "joint5", "joint6"]  # 对应关节的名称
        # single_arm.set_joint_positions(positions=positions,duration=0)
        # single_arm.set_gripper_pos(-1)

        #
        # duration = 多少秒到达 (量化到 0.01s)
        #   set_joint_positions(positions, duration=3)   3 秒慢慢走过去
        #   set_joint_positions(positions, duration=0)   原始最大速度


        # print(single_arm.get_ee_pose_xyzrpy())
        # print(single_arm.get_joint_positions())
        # print(single_arm.get_joint_velocities())
        # print(single_arm.get_joint_currents())


        tick(n, "运行中 (Ctrl+C 退出)"); n += 1

        time.sleep(0.01)



if __name__ == "__main__":
    arm_config: Dict[str, Any] = {
        "can_port": "can1",
        "type": 0,
        # 0>2023  2>2025  3>A5
        # "urdf_path": "A5-heavy.urdf",   # 可选: 该臂自己的 URDF, 相对 bimanual/models/ (复制机型 URDF 只改 link6 质量)
    }
    try:
        with Loading(f"连接 {arm_config['can_port']} / 初始化"):
            single_arm = SingleArm(arm_config)
    except RuntimeError as e:
        sys.exit(f"\n{e}")
    try:
        test_single_arm(single_arm)
    except KeyboardInterrupt:

        print("\nCtrl+C -> 阻尼保护")
        single_arm.go_home(0.5, wait=True)
        single_arm.damp(2.0)
    finally:
        single_arm.close()
