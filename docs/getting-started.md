# Your first experiment

**[Play Courtyard Block](https://crs48.github.io/courtyard-block/play/)** in your browser, or open `project.godot` in Godot 4.7.2 and press F5. The browser downloads the game on first launch; allow a moment for it to start.

Your community has eight homes and 24 neighbours. You are exploring a question: **can we make their homes warmer without making life less affordable?** There is no winning score. Every change is another experiment.

## Start with one change

1. Open **Design** and change **Light timber wall** to **Insulated timber wall**.
2. Select **Run 90 days**. Your design and the reference live through the same winter, with the same weather and households.
3. Open **People** and choose a household, or select its home in the scene. Look at cold hours, bills and unpaid bills. Averages can hide a household that is struggling.
4. Open **Compare**. Did comfort improve? How much did construction cost? What happened to energy demand?
5. Choose **Try again**. Keep what helped, change one more thing, and rerun the winter. When you are ready, **Run 1 year** includes summer too.

## Three questions to try

| Question | Change | Watch |
| --- | --- | --- |
| Do shared walls help? | Courtyard versus detached cluster | Heat demand and construction cost |
| Can storage help during an outage? | Battery capacity and water storage | Unserved electricity, water shortages and sewage overflow |
| Who pays for a shared system? | Equal versus metered billing | Individual bills, arrears and the operating reserve |

These are illustrative scenarios. The model has physical and accounting checks, but its default data has not been calibrated against a real community. Read the [model boundaries](lab.md#physics-and-accounting-boundaries) before interpreting a result as a real-world forecast.

## Move around

Drag the scene to pan. Use the mouse wheel, a pinch, or the **+ / −** buttons to zoom. **Turn**, Q and E rotate the view. Space pauses an active run. On a phone, **Scene / Details** switches between the scene and the controls; panels scroll. All essential actions have on-screen controls.

## Make something that is yours

Open **Workshop** to create a material and wall. Give the pack a unique ID, adjust its properties, and select **Create a draft pack**. Review the JSON, then **Validate & add to this experiment**. Your wall becomes an option in Design. The [data mod guide](data-reference.md) explains the next steps.

The workshop can also import a complete year of hourly weather and export a prompt for an AI assistant. Nothing is automatically sent to an AI service. Check generated numbers and sources before treating them as evidence.

## Keep it and share it

**Export experiment** bundles the inputs, installed data packs, question and recorded time. A friend can use **Compare → Import a friend's experiment** to replay it. **Export mod** shares just your reusable material or other definitions.

The game autosaves locally. Browser storage can be cleared, and the six-entry trial notebook lasts only for the current session. Export experiments you want to keep. A shared experiment belongs to a particular model runtime; future incompatible versions may require the original executable to replay it.

Continue with the [complete community lab guide](lab.md), or [contribute a new experiment](../CONTRIBUTING.md).
