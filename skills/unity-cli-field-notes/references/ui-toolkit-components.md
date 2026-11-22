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

## Lists, drag, per-entity views

- `BaseVerticalCollectionView.makeItem` and `bindItem` are `[Obsolete]`. Set them on `ListView`. Call `RefreshItems()` only when the row count changes. Bound rows re-evaluate through their data source's version.
- In a test, a synthesized drag reaches pointer capture and `panel.Pick`. Send each of these with `target.SendEvent(e)`:
  - `PointerEventBase<PointerDownEvent>.GetPooled(new Event { type = EventType.MouseDown, mousePosition = panelPos, button = 0 })`
  - then the same with `MouseDrag` and `PointerMoveEvent`
  - then `MouseUp` and `PointerUpEvent`
- A `NativeArray` from `Allocator.Temp` held across a `yield return` in a PlayMode test throws `ObjectDisposedException`. Copy it first with `.ToArray()`.
- Placing a pooled view over each entity with `RuntimePanelUtils.CameraTransformWorldToPanel` and an inline `style.translate` every frame allocates 0 B once the views exist.
