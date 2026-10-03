# 03 — Platform and performance validation

Use the Compatibility renderer and typed GDScript across platforms. Batch static geometry by floor and material, cache routes, and separate logical ticks from rendering. Browser file access uses a narrow JavaScript bridge; native platforms use their file picker.

- [ ] Test logic and persistence in headless Godot
- [ ] Render and exercise the native game
- [ ] Export and exercise the browser game
- [ ] Export Android and iOS development builds when matching templates are available
- [ ] Test mobile layouts and touch flows in simulators
- [ ] Measure native, browser, and physical mobile frame times

The reference load is 150 residents, seven storeys, 5,000 furnishings, and 10,000 catalogue definitions. Target 16.7 ms p95 frame time after warm-up and sustained operation on physical devices. Document exact hardware, export mode, viewport, and all unverified targets. Preserve unmet validation items as unchecked.
