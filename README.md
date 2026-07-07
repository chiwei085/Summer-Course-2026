# Summer Course

Hands on labs for a robotics software summer course. Every lab is
self contained and carries its own `README.md` (or `LESSON.md`) with build,
run, and grading instructions. Start from the lab's own document, not from
here.

This branch is the **student version**. Three homework labs ship in a
deliberately incomplete state and are yours to finish (see
[Homework](#homework) below). Everything else is reference material you run,
read, and experiment with.

## Week 1: Engineering Toolbox

| Lab | What it is |
| --- | --- |
| [ssh/](week1/ssh/ssh-field-lab-distribution/) | A remote-operations mission. Restore a robot navigation service over SSH on two Docker nodes. |
| [git/](week1/git/git-merge-lab-distribution/) | A generated repository for practicing merge decisions. Observe, predict, decide. |
| [docker/](week1/docker/visual-relay/) | **Homework.** Containerize a distributed cross-camera robot vision system. |

## Week 2: Learning Based Robotics (Python)

A single [uv](https://docs.astral.sh/uv/) project. From `week2/`, run
`uv sync` and drive everything through `uv run python cli.py`. Each lab's
`LESSON.md` is the step by step lesson material.

| Lab | What it is |
| --- | --- |
| [basic_regression_classification/](week2/basic_regression_classification/) | Linear and MLP models on regression and classification tasks. |
| [basic_sequence_bc/](week2/basic_sequence_bc/) | Sequence behavior cloning, from bigram to transformer. |
| [basic_vision_representation/](week2/basic_vision_representation/) | Vision representations for downstream policies. |
| [homework/](week2/homework/) | VLA capstone. Vision state, language instruction, and action sequence meet in one BC policy. |

## Week 3: Classical Vision (C++20, no OpenCV)

Interactive notebook style labs. Each one builds a small HTTP server and
renders in your browser like a live notebook.

| Lab | What it is |
| --- | --- |
| [color/](week3/color/) | Classic color space operations from scratch. |
| [local-geometry/](week3/local-geometry/) | Local feature and geometric primitive detectors from scratch. |
| [calibration/](week3/calibration/) | Pinhole camera calibration from real chessboard images, with interactive reprojection diagnostics. |
| [homework/](week3/homework/) | **Homework.** Snake (active contour) segmentation. |

## Week 4: SE(3) Control and Trajectories

C++20 with Conan 2, CMake, Sophus, and Eigen.

| Lab | What it is |
| --- | --- |
| [basic/](week4/basic/) | Sophus SE(3) closed loop drone pose tracking. |
| [advanced/](week4/advanced/) | UR5 style 6R arm cube pick and place. |
| [homework/](week4/homework/) | **Homework.** PX4 style raw mission to `TrajectorySetpoint` pipeline. |

## Week 4.5: ROS 2 TF and Concurrency

| Lab | What it is |
| --- | --- |
| [tf_ws/](week4.5/tf_ws/) | Fleet ops diagnostic shift. A multi threaded ROS 2 (Jazzy) warehouse AMR stack with four real bugs hidden inside. Find and fix them. |

## Homework

The three graded labs, and what "done" means for each:

1. **Week 1, [visual-relay](week1/docker/visual-relay/)**. You get the worst
   `Dockerfile`, `compose.yaml`, and `.dockerignore` that still run. Rebuild
   them into a deployment fit for production. Done when `./grader/grade.sh`
   is fully green.
2. **Week 3, [snake](week3/homework/)**. The whole pipeline is provided
   except the active contour update itself, which is a `TODO` in
   `src/snake.cpp`. Done when the contour converges onto the object in all
   three sample images.
3. **Week 4, [trajectory](week4/homework/)**. The mission parser, plant
   simulation, and diagnostics are provided. The segment duration sizing,
   setpoint sampling, and tracking law are `TODO`s. Done when the program
   prints `result: passed`.

Each homework directory's own README states the task, the constraints, and
the grading workflow in full.
