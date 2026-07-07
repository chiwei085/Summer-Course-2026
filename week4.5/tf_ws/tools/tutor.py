#!/usr/bin/env python3
"""Fleet Ops tutor for the fleet_tf_lab ROS 2 package.

Not part of the colcon workspace -- lives outside src/ on purpose so a
`colcon build` never tries to treat this script as a package.
"""

import glob
import os
import subprocess
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "fleet_tf_lab"
EXECUTABLE = ROOT / "install" / PACKAGE / "lib" / PACKAGE / f"{PACKAGE}_node"
RUN_TIMEOUT_SECONDS = 20


def section(title: str) -> None:
    print()
    print(title)
    print("─" * 64)


def ask_choice(question: str, options: Sequence[str], correct: str | None = None) -> str:
    print()
    print(textwrap.fill(question, width=72))
    for index, option in enumerate(options, start=1):
        print(f"[{index}] {option}")

    valid = {str(i) for i in range(1, len(options) + 1)}
    while True:
        answer = input("> ").strip()
        if answer not in valid:
            print("Please enter the option number.")
            continue
        if correct is not None and answer != correct:
            print("Try again -- look for clues in the observations above.")
            continue
        return answer


def wait_for_enter(
    prompt: str = "\nAfter editing the code, press Enter to rebuild and run again...",
) -> None:
    input(prompt)


def find_ros_setup() -> Path | None:
    if os.environ.get("AMENT_PREFIX_PATH"):
        return None  # Already sourced by the caller's shell.
    candidates = sorted(glob.glob("/opt/ros/*/setup.bash"), reverse=True)
    return Path(candidates[0]) if candidates else None


def shell_command(inner: str) -> list[str]:
    ros_setup = find_ros_setup()
    prefix = f"source {ros_setup} && " if ros_setup else ""
    return ["bash", "-c", f"{prefix}{inner}"]


@dataclass
class BuildResult:
    ok: bool
    output: str


def build_package() -> BuildResult:
    result = subprocess.run(
        shell_command(
            f"cd {ROOT} && colcon build --symlink-install "
            f"--packages-select {PACKAGE} --cmake-args -DCMAKE_BUILD_TYPE=Release"
        ),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return BuildResult(ok=result.returncode == 0, output=result.stdout)


@dataclass
class RunResult:
    timed_out: bool
    output: str
    stage1: bool | None = None
    stage2: bool | None = None
    stage3: bool | None = None
    stage4: bool | None = None
    summary_line: str | None = None

    def stage_passed(self, stage_number: int) -> bool | None:
        return getattr(self, f"stage{stage_number}")

    def first_failing_stage(self) -> int | None:
        return next(
            (
                stage.number
                for stage in STAGES
                if self.stage_passed(stage.number) is not True
            ),
            None,
        )


def run_node() -> RunResult:
    command = shell_command(f"cd {ROOT} && source install/setup.bash && {EXECUTABLE}")
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=RUN_TIMEOUT_SECONDS,
        )
        output = result.stdout
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        output = exc.output or b""
        timed_out = True

    if isinstance(output, bytes):
        output = output.decode("utf-8", errors="replace")

    run = RunResult(timed_out=timed_out, output=output)
    for line in output.splitlines():
        if line.startswith("[SUMMARY]"):
            run.summary_line = line
        elif line.startswith("[STAGE1]"):
            run.stage1 = "PASS" in line
        elif line.startswith("[STAGE2]"):
            run.stage2 = "PASS" in line
        elif line.startswith("[STAGE3]"):
            run.stage3 = "PASS" in line
        elif line.startswith("[STAGE4]"):
            run.stage4 = "PASS" in line
    return run


@dataclass(frozen=True)
class Stage:
    number: int
    label: str
    question: str
    options: Sequence[str]
    hints: Sequence[str]
    correct: str = "2"

    @property
    def scorecard_label(self) -> str:
        return f"STAGE{self.number} ({self.label})"


STAGES = (
    Stage(
        number=1,
        label="state pipeline freshness",
        question=(
            "STAGE1 is failing: odom -> base_link freezes for stretches of "
            "roughly half a second at a time -- and map -> odom freezes in "
            "the same windows -- while dock detections and clearance "
            "telemetry keep flowing the whole time. Meanwhile the pose "
            "error in STAGE2 spikes to tens of centimeters during exactly "
            "those windows. What does that pattern suggest?"
        ),
        options=(
            "The whole node is crashing and restarting",
            "The frozen publishers share an execution context with "
            "something that isn't giving it back",
            "The TF messages are being dropped by the network",
            "The encoder driver thread is dying",
        ),
        hints=(
            "Notice WHICH things freeze together and which don't. The "
            "camera detections and the clearance writes come from plain "
            "background threads and never stall. The two transforms that DO "
            "stall are both published from rclcpp timer callbacks. Where do "
            "those callbacks run, and what determines when they get a turn? "
            "Also note the order of battle: pose ACCURACY numbers can't be "
            "trusted while the pipeline's FRESHNESS is broken -- chase the "
            "freeze first, not the biggest error.",
            "In main.cpp, wheel_odom_timer_, scan_matcher_timer_ and "
            "dock_controller_timer_ all share state_estimation_group_, a "
            "MutuallyExclusive callback group. That guarantees no two of "
            "them ever run at the same time -- and it equally guarantees "
            "that if ONE of them doesn't return, the other two never run "
            "again until it does. Which of the three has a reason to wait "
            "around for data that only arrives every ~600 ms?",
            "Read runDockApproachTick(). It loops until it sees a fresh "
            "dock sighting, with nothing inside the loop that returns "
            "control -- a busy-wait. The camera only publishes every 600 "
            "ms, so each tick can spin for up to ~600 ms while odometry and "
            "localization are locked out. Note: adding a sleep_for() inside "
            "the loop cuts CPU but the callback STILL doesn't return, so "
            "the siblings stay starved. The real fix is to make the "
            "callback return promptly: check once, and if the sighting is "
            "stale, return and try again next tick. (Moving the controller "
            "to its own group hides the symptom but leaves a thread "
            "spinning -- returning early is the honest fix.)",
        ),
    ),
    Stage(
        number=2,
        label="localization accuracy",
        question=(
            "STAGE2 is failing: the robot's believed pose in map is off by "
            "~15 cm -- suspiciously close to what Unit 12 travels in 150 ms "
            "-- and the error tracks the robot's speed. Nothing throws, "
            "nothing is stale anymore, the numbers are just wrong. What "
            "kind of bug produces an error proportional to speed x latency?"
        ),
        options=(
            "Random sensor noise",
            "Two pieces of state sampled at different times being combined "
            "as if they were simultaneous",
            "A unit conversion error (degrees vs radians)",
            "A memory corruption race",
        ),
        hints=(
            "An error that scales with velocity is a TIME error wearing a "
            "position costume. The localization correction is built by "
            "combining two things: the scan matcher's answer and wheel "
            "odometry. Each of those describes the robot's pose AT some "
            "instant. Are they describing the SAME instant?",
            "In runScanMatcherTick(), the matched pose is computed for "
            "scan_t -- the moment the laser scan was TAKEN, 150 ms ago. "
            "Then it's combined with an odometry transform. Look at the "
            "time argument of that lookupTransform call: what instant does "
            "tf2::TimePointZero actually ask for?",
            "tf2::TimePointZero means 'latest available', i.e. the robot's "
            "odometry NOW -- but the matched pose describes where the robot "
            "was 150 ms AGO. Subtracting poses from two different instants "
            "bakes 150 ms of motion into the map->odom correction. The TF "
            "buffer keeps history precisely for this: look up odom -> "
            "base_link AT the scan's own stamp (pass scan_stamp instead of "
            "TimePointZero) so both halves of the equation describe the "
            "same moment.",
        ),
    ),
    Stage(
        number=3,
        label="dock perception",
        question=(
            "STAGE3 is failing: the believed dock-marker pose in map is "
            "meters away from the surveyed dock position and rotated by "
            "some large, CONSTANT amount -- while localization (STAGE2) now "
            "checks out and the detections themselves arrive on schedule. "
            "What kind of bug produces a large, consistent pose error "
            "without ever throwing or failing a build?"
        ),
        options=(
            "A race condition that corrupts memory randomly",
            "A wrong but internally consistent static geometry value",
            "A dropped ROS message",
            "A missing package dependency",
        ),
        hints=(
            "The error is big but perfectly repeatable -- the same wrong "
            "answer every run, every tick. Randomness (races, drops) "
            "doesn't look like that. The moving parts of the chain "
            "(localization, the detection stream) have been cleared. What "
            "part of the map -> dock_marker chain is published exactly once "
            "at startup and never changes?",
            "Walk every static mount the robot publishes in "
            "publishStaticFrames(): laser, IMU, mast, camera body, and one "
            "more frame after the camera body. Which of those is not simply "
            "describing where a rigid part is bolted on, but describing an "
            "AXIS-CONVENTION change?",
            "Look at how camera_link -> camera_optical_frame is assembled. "
            "ROS mechanical frames are x-forward/y-left/z-up; optical "
            "frames are z-forward/x-right/y-down (REP-103). The comment "
            "says the rotation is applied -- is it actually? The detector "
            "reports the marker in OPTICAL axes; interpret that in "
            "mechanical axes and a marker 4 m ahead lands meters from where "
            "it really is. (geometry::cameraOpticalRotation() exists for a "
            "reason.)",
        ),
    ),
    Stage(
        number=4,
        label="safety telemetry throughput",
        question=(
            "STAGE4 is failing: the lidar clearance writer barely commits "
            "any updates all run, even though every reader thread is "
            "behaving and blocking properly (no busy-waiting anywhere "
            "here). What category of problem is this?"
        ),
        options=(
            "Busy-waiting (a thread wasting CPU in a spin loop)",
            "A fairness/starvation problem in the locking policy itself",
            "A memory leak",
            "A missing mutex entirely",
        ),
        hints=(
            "The clearance writer only got a handful of updates through the "
            "whole run, while six consumer threads polled the cache "
            "constantly and without incident. Nobody is spinning -- every "
            "thread blocks properly on something. So why would a perfectly "
            "well-behaved writer almost never get its turn?",
            "Look at NaiveReaderPreferringLock in clearance_cache.hpp. When "
            "a new reader arrives, what does it check before joining the "
            "readers already inside? Does it ever look at whether a writer "
            "is WAITING?",
            "This is the classic first-readers-writers problem: as long as "
            "at least one reader is always active, the writer can wait "
            "forever, even though every individual thread behaves. Fix the "
            "lock so a WAITING writer blocks any NEW readers from starting "
            "until it has run (a writer-preferring or fair policy): track a "
            "waiting_writers_ count, make lockRead() wait until no writer "
            "is active AND none is waiting, and have lockWrite() increment "
            "the count before it waits.",
        ),
    ),
)
STAGE_BY_NUMBER = {stage.number: stage for stage in STAGES}


def print_hint(hints: Sequence[str], attempts: int) -> None:
    index = min(attempts, len(hints) - 1)
    print()
    print(textwrap.fill(hints[index], width=72))


def print_intro() -> None:
    section("Fleet Ops -- Unit 12 Diagnostic Shift")
    print(
        textwrap.dedent(
            """
            You're the on-call engineer for a warehouse AMR fleet. Unit 12
            has been missing delivery windows and bumping its dock approach
            lately, and Fleet Ops has escalated it to you. The robot's own
            logs look fine at a glance -- nothing crashes, nothing throws.
            All you have is a diagnostic build of Unit 12's navigation stack
            (fleet_tf_lab) and the warehouse's external tracking rig, which
            Fleet Ops uses to grade what the robot believes against reality.
            """
        ).strip()
    )

    print()
    print("Unit 12's frame tree:")
    print(
        textwrap.dedent(
            """
              map                          (scan matcher publishes map -> odom)
               └─ odom                     (wheel odometry publishes odom -> base_link)
                   └─ base_link
                       ├─ laser_link      (static)
                       ├─ imu_link        (static)
                       └─ mast_link       (static)
                           └─ camera_link (static)
                               └─ camera_optical_frame (static)
                                   └─ dock_marker      (fiducial detection)
            """
        ).strip("\n")
    )

    print()
    print("Concurrency in the diagnostic build:")
    print(
        textwrap.dedent(
            """
              - state_estimation_group : wheel odometry + scan matcher +
                dock approach controller (one MutuallyExclusive group -- they
                all touch the pose estimate, so they are serialized)
              - uplink_group           : fleet telemetry uplink
              - encoder driver, dock camera driver, lidar clearance writer,
                and 6 clearance consumers: plain std::thread workers outside
                the executor entirely (like real sensor drivers), sharing a
                hand-rolled clearance telemetry cache.
            """
        ).strip("\n")
    )

    print()
    print(
        textwrap.fill(
            "Each shift, you'll build the diagnostic image, run one timed "
            "delivery leg toward the charging dock, and read Fleet Ops' "
            "scorecard. Expect the symptoms to overlap: one root cause can "
            "light up several gauges at once, so fix what the evidence "
            "points at, rerun, and watch which numbers move. Nothing here "
            "will tell you outright which file or line is broken -- that's "
            "your job as the on-call engineer.",
            width=72,
        )
    )


def print_scorecard(run: RunResult) -> None:
    print()
    print("Fleet Ops scorecard for this session:")
    label_width = max(len(stage.scorecard_label) for stage in STAGES)
    for stage in STAGES:
        status = "PASS" if run.stage_passed(stage.number) else "FAIL"
        print(f"  {stage.scorecard_label:<{label_width}} : {status}")
    if run.summary_line:
        print()
        print(f"  raw telemetry: {run.summary_line}")


def print_debrief() -> None:
    section("Shift complete -- Unit 12 cleared for duty")
    print(
        textwrap.dedent(
            """
            You worked through four faults that were each true to how they
            show up on real robots -- and, like on real robots, their
            symptoms overlapped:

            1. A busy-wait inside a MutuallyExclusive callback group starved
               its siblings: odometry froze, localization froze with it, and
               the pose error exploded -- so a pure CONCURRENCY bug read as
               a TF/localization failure on the scorecard. Merely adding a
               sleep_for() would not have fixed it: the callback had to
               RETURN.

            2. Only after freshness was restored could you see the real
               localization defect: a scan matched 150 ms ago paired with
               odometry from NOW. TimePointZero ("latest") is not "the same
               time as my data" -- TF keeps history so you can ask for the
               instant you actually mean.

            3. A silently wrong static transform (the camera's REP-103
               optical-frame rotation) that compiled fine, published fine,
               and only showed up as the dock marker living meters from
               where the survey says it is.

            4. A reader-preferring lock in a hand-rolled telemetry cache,
               where every thread behaved correctly and blocked properly,
               yet the writer could still starve forever -- the classic
               first-readers-writers problem.

            The meta-lesson: on a live system you rarely get one clean
            symptom per bug. Establish freshness before you trust accuracy,
            grade beliefs against ground truth at the SAME instant, and
            suspect policies (scheduling, locking, time pairing) before you
            suspect the numbers.
            """
        ).strip()
    )


def main() -> None:
    try:
        print_intro()
        attempts = {stage.number: 0 for stage in STAGES}
        introduced_stage: set[int] = set()

        while True:
            build = build_package()
            if not build.ok:
                section("colcon build failed")
                print(build.output[-4000:])
                wait_for_enter()
                continue

            print()
            print("Build OK. Running Unit 12 for one diagnostic session...")
            run = run_node()

            if run.timed_out or run.stage1 is None:
                section("Session did not report a scorecard")
                print(
                    "The process did not exit on its own within "
                    f"{RUN_TIMEOUT_SECONDS}s, or produced no [SUMMARY] line."
                )
                print(
                    "If you've been editing the clearance cache lock, this "
                    "can mean two threads are waiting on each other forever "
                    "(a deadlock) rather than one starving the other."
                )
                print()
                print(run.output[-4000:])
                wait_for_enter()
                continue

            print_scorecard(run)

            active_stage_number = run.first_failing_stage()
            if active_stage_number is None:
                print_debrief()
                return

            active_stage = STAGE_BY_NUMBER[active_stage_number]
            if active_stage.number not in introduced_stage:
                introduced_stage.add(active_stage.number)
                ask_choice(
                    active_stage.question,
                    active_stage.options,
                    correct=active_stage.correct,
                )

            print_hint(active_stage.hints, attempts[active_stage.number])
            attempts[active_stage.number] += 1

            wait_for_enter()

    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(130)


if __name__ == "__main__":
    main()
