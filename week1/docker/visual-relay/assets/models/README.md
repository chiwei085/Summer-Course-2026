# Visual Relay Reference Models

The runtime renderer is intentionally lightweight SDL, but these OBJ assets are
installed into the container image and describe the scene pieces expected by the
assignment design: conveyor, tunnel, guard rails, warning lights, Scout camera
rig, Catcher arm rig, bins, and five distinguishable objects.

They are simple enough for teaching review and future replacement by a glTF or
Magnum renderer without changing the scene contract in `assets/scene/scene.json`.
