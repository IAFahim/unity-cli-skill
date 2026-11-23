# UI Toolkit components and runtime lists (verified 7000.0.0a16)

Verified in `-batchmode -nographics` PlayMode tests, with components declared both in an `Assets/` asmdef and in a `file:` package asmdef.

## Components: `[VisualElementComponent]`

- A `[VisualElementComponent] public partial struct T` gets its `IVisualElementComponent` implementation from Unity's built-in generator (`Editor/Data/Tools/BuildPipeline/Unity.SourceGenerators/Unity.UIToolkit.SourceGenerator.dll`). It runs on any asmdef that references UIElements, with no extra setup. The generator rejects nested and generic component types.
- Handlers are static: `[RegisterCallback(typeof(ClickEvent))] static void M(ref T self, VisualElement owner, ClickEvent evt)`. Generic events work too (`ChangeEvent<float>`, `ChangeEvent<int>`, `ChangeEvent<bool>`). `[RequiresElementOfType(typeof(Button))]` lets the owner parameter be typed `Button`. `[RequiresComponentOfType(typeof(U))]` adds `U` first, through `GetOrAddComponent`.
- `element.AddComponent(new T { ... })`, `ref T GetComponent<T>()`, `HasComponent<T>()`, `RemoveComponent<T>()`.
  - An unmanaged struct lives in a per-type native store. A struct with a managed field is boxed one instance at a time.
  - Each event handler is one shared definition per type, so nothing is allocated per element.
  - Measured: 1000 rounds of `GetComponent` + `HasComponent` + a synthesized click + `MarkComponentDirty` allocated 0 B warm.
- `MarkComponentDirty<T>()` defers `[OnComponentChanged] static void M(ref T self, VisualElement owner)` to the panel's update. Two marks in one frame run it once.
- UXML: a component is a child node of its element, named by the struct's full type name.
  - Example: `<ui:Button><my:Send code="1" /></ui:Button>` with `xmlns:my="My.Namespace"`.
  - `[UxmlAttribute]` fields become kebab-case attributes (`RowAsPayload` -> `row-as-payload`).
  - A `ulong` attribute keeps all 64 bits. An enum attribute parses by name.
  - Components attach during `CloneTree`, before the element has a panel: a `VisualTreeAsset.Instantiate()` that never joined a panel already reports `HasComponent<T>()`. Read them from the PanelRenderer reload callback.
- The UXML importer keeps `class`, `style`, `slot`, `slot-name` and `content-container` for itself, on component nodes too. A component field named `Slot` is dropped silently and keeps its default. Give such fields another name, and test every attribute with a non-default value.
- `[VisualElementComponent(name = "Send")]` is ignored by the UXML registry, which honours custom names only for `UxmlElement`. Using the custom name logs `Element 'Ns.Send' is missing a UxmlElementAttribute`. Author the struct name.
- `[UxmlCreateInstanceMethod] public static T Defaults() => new T { Scale = 1f };` sets the values a UXML-created component starts with when the UXML leaves out an attribute.
- **Project Settings > UI Toolkit > Enable UI Components** (stored in `ProjectSettings/UIToolkitProjectSettings.asset`) only shows a Components section in the UI Builder element inspector. Components work at runtime and from UXML without it. The setting is marked experimental.
- Generator diagnostics are `UITKSG0xx`. Two of them warn on code that compiles:
  - `UITKSG044`: fields declared in an order that wastes padding.
  - `UITKSG029`: a `[UxmlAttribute]` field written through a `ref` with no `NotifyComponentChanged` after it.
  - Keep runtime-only fields off `[UxmlAttribute]`. Grep the batch log for `warning` and `UITKSG`, not only `error CS`.
- A static handler can find its owning MonoBehaviour without a stored reference. Walk `owner.hierarchy.parent` until an element equals a root that an enabled host registered from its PanelRenderer reload callback. Clear that static list on `SubsystemRegistration`.
- With C# 9, a `ref` local inside a test coroutine is a compile error (`CS8773`). Move `ref var c = ref e.GetComponent<T>()` into a helper method. Reading `e.GetComponent<T>().Field` inline is fine.

## Keyboard, gamepad and ListView interaction

- `ClickEvent` comes only from pointers. A `Button` turns Submit (`NavigationSubmitEvent`, sent to the focused element: Enter or gamepad South) into `Clickable.clicked`, never into `ClickEvent`. A handler that registers only `ClickEvent` is dead for keyboard and gamepad. Register `NavigationSubmitEvent` too, and set `focusable = true` on elements that are not already focusable.
- In a runtime panel, a reorderable `ListView`'s own drag works with synthesized pointer events: down on a row, move at least 10 px with the button held, then up over another row.
  - `handleDrop` receives `dropPosition` and `insertAtIndex`. `OverItem` gives the row index; `BetweenItems` gives the insert slot.
  - Returning `DragVisualMode.Move` accepts the drop and skips the view's own reorder, so `itemsSource` stays as it was and your code decides.
  - The dragged row is `selectedIndex`.
- `ListView.SetSelection(i)` raises `selectedIndicesChanged` at once. A `NavigationSubmitEvent` on the view reaches callbacks registered on it, which can read `selectedIndex`.
- A `DataBinding` with `BindingMode.TwoWay` from a Slider or Toggle to a `[CreateProperty]` field of a ScriptableObject data source writes the asset in the next frames at runtime. Other bindings on that field follow.

## What a16 already has

- The 7000.0.0a16 UIElements module already contains the features docs list for Unity 6.3 to 6.7:
  - USS `filter`, `drop-shadow`, `backdrop-filter`, `aspect-ratio`, `gap`, and grid display;
  - UI animation clips (`animation-name`);
  - `VisualElementReference`;
  - `PanelSettings.extraVertexChannels` and `AddMeshModifier`;
  - `TextElement.PostProcessTextVertices`;
  - `TabView`, `RepeatButton`, `ToggleButtonGroup`, `VectorImage` and `Painter2D`.
- Check the decompiled module before you build any of these yourself.
- One `VisualElement.schedule.Execute(action)` item, created once and paused, can be re-armed with `ExecuteLater(ms)` for a delayed show, such as a runtime tooltip. Focus moves between two tooltipped buttons (`FocusInEvent` on the root, text and inline position writes) measured 0 B warm.

## Custom bindings and measuring UI Toolkit's own work

- A custom binding type works from UXML `<Bindings>` and from C#:
  - Declare `[UxmlObject] public partial class X : DataBinding` and override `protected override BindingResult UpdateUI<TValue>(in BindingContext context, ref TValue value)`.
  - Read the source value without boxing: `typeof(TValue) == typeof(float)` plus `UnsafeUtility.As<TValue, float>(ref value)`.
  - `[UxmlAttribute]` fields of enum, float and bool type parse; this was tested with non-default values.
  - Set `bindingMode = BindingMode.ToTarget` in the constructor.
  - Returning `new BindingResult(BindingStatus.Pending)` makes UI Toolkit retry next update.
- Native bindings worth knowing:
  - `enabledSelf` binds directly, for example a bool through a `!value` converter group.
  - `DropdownField.index` (`PopupField<T>.index`, `[CreateProperty]`) binds TwoWay to an int.
  - The `tooltip` field binds.
- To measure what UI Toolkit itself allocates (bindings, scheduled items, components), insert two `PlayerLoopSystem`s around the subsystem whose `type.Name` is `UIElementsUpdatePanels`. Have them read `GC.GetAllocatedBytesForCurrentThread()`. Measured 0 B over 239 ticks with standard DataBindings, three custom DataBinding subclasses and a Painter2D element whose ECS-backed source changed every frame.
- A hotkey reference that survives a saved scene:
  - Create `ScriptableObject.CreateInstance<InputActionAsset>()`, call `AddActionMap(..).AddAction(.., binding: "<Keyboard>/p")`, and save it with `AssetDatabase.CreateAsset` as `.asset`.
  - Call `InputActionReference.Create(action)` and attach the result with `AssetDatabase.AddObjectToAsset(reference, asset)`.
  - A field holding that reference keeps `action` after the scene is reopened, and the hotkey fires in PlayMode.

## Lists, drag, per-entity views

- `BaseVerticalCollectionView.makeItem` and `bindItem` are `[Obsolete]`. Set them on `ListView`. Call `RefreshItems()` only when the row count changes. Bound rows re-evaluate through their data source's version.
- In a test, a synthesized drag reaches pointer capture and `panel.Pick`. Send each of these with `target.SendEvent(e)`:
  - `PointerEventBase<PointerDownEvent>.GetPooled(new Event { type = EventType.MouseDown, mousePosition = panelPos, button = 0 })`
  - then the same with `MouseDrag` and `PointerMoveEvent`
  - then `MouseUp` and `PointerUpEvent`
- A `NativeArray` from `Allocator.Temp` held across a `yield return` in a PlayMode test throws `ObjectDisposedException`. Copy it first with `.ToArray()`.
- Placing a pooled view over each entity with `RuntimePanelUtils.CameraTransformWorldToPanel` and an inline `style.translate` every frame allocates 0 B once the views exist.
- A drag that moves the element holding pointer capture to another parent (to draw it above the other lists) broke the drag in a synthesized-pointer test: the hover target was never marked (verified 7000.0.0a20). What works there, in PlayMode tests and in CoreCLR and IL2CPP players:
  - Leave the dragged element in place, holding the capture, and give it a class (dim it in USS).
  - Draw a ghost on top instead: `VisualTreeAsset.Instantiate()` of the same row template, `pickingMode = Ignore`, `position: absolute`, the same `dataSource` and `dataSourcePath`, added once to the panel root, then `BringToFront()`. Move it with `style.left` and `style.top` from `root.WorldToLocal(row.worldBound.position)` plus the pointer delta.
  - To find what is under the pointer, use `IPanel.PickAll(point, reusedList)`, and skip the ghost, the dragged element and their descendants (`element.Contains(picked)`).
- A `[VisualElementComponent] partial struct` can hold managed fields, such as a `VisualElement` or a `List<VisualElement>`, and mutate them through `ref self` in its `[RegisterCallback]` handlers. Per-element drag state lives there, with no statics (verified 7000.0.0a20).

## Player builds (verified 7000.0.0a16, Linux)

- `ScriptingImplementation` has `CoreCLR` (the default) and `IL2CPP`. `PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, ...)` switches between them. Restoring the old value afterwards writes `Standalone: 3` (CoreCLR) into ProjectSettings explicitly.
- `BuildPipeline.BuildPlayer` with SubScene scenes produces a player whose entity scenes bake and load, with no extra build package.
- In both backends these load from UXML and run, with no `link.xml`:
  - `[VisualElementComponent]` structs;
  - `[UxmlObject]` DataBinding subclasses;
  - a `[UxmlElement]` Painter2D element.
- A `-batchmode -nographics` player runs ECS and UI Toolkit (events, bindings, scheduled items, data binding). `Application.Quit(code)` becomes the process exit code, so a smoke scene can gate CI.
- A UPM Git dependency with `?path=/<package>#<branch>` installs a package from a subfolder of a repository. List every Git package of the set in the project manifest.

## Panel settings that do not stick, and seeing a frame (verified 7000.0.0a20)

- A `UIDocument` built by an editor script loses its panel settings on save: `doc.panelSettings = ps` and writing `m_PanelSettings` through `SerializedObject` both end as `m_PanelSettings: {fileID: 0}` in the scene (batch, with and without `-nographics`), while a `PanelSettings` field on your own MonoBehaviour saves fine. Give your component the reference and assign `doc.panelSettings` at runtime when it is null.
- To see a running scene headless: a PlayMode test in a batch Editor without `-nographics` sets `Camera.main.targetTexture`, clones the panel settings with `targetTexture`, `clearColor = true`, `colorClearValue = clear`, waits a few frames, calls `Camera.Render()`, reads both RenderTextures with `ReadPixels` and alpha-composites them. With the image-conversion module absent (`Texture2D.EncodeToPNG` is CS1061), write a binary PPM (`P6`, rows top first) and convert outside Unity.

## Screenshots of runtime UI with no display (verified 7000.0.0a20, Linux)

- `-batchmode` without `-nographics` creates an OpenGL Core device with no X or Wayland display (`OPENGL LOG: Creating OpenGL 4.6 graphics device`). So a batch Editor can enter Play mode and render real UI images:
  1. `EditorApplication.EnterPlaymode()` from `-executeMethod`, with no `-quit`, and finish with `EditorApplication.Exit(0)`.
  2. Copy the screen's `PanelSettings` with `Instantiate`, set `targetTexture` to a `RenderTexture` and `clearColor = true`, and assign the copy to the `PanelRenderer`. The UI rebuilds; a Tl UI Panel resolves again on its reload callback.
  3. Read the texture with `RenderTexture.active` and `Texture2D.ReadPixels`, then write it with `EncodeToPNG`.
- Synthesized pointer events, ECS systems and Tl timelines all run there.
- Wait in wall-clock time (`Stopwatch`), plus a few `Time.frameCount` frames. An `EditorApplication.update` driver must step into nested `IEnumerator`s itself, or every nested wait passes after one tick.
- In those captures, labels drawn in the first seconds came out blank after about 3 s of play. Setting every `TextElement.text` to "" for two frames, then back, before each capture brought the text back. The cause is not confirmed.
- Only runtime panels render this way. Editor windows (Inspector, Timeline, UI Builder) need a real or virtual display.
