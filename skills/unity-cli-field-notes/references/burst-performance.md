# Burst / ECS performance: recipes, wins, dead ends

Verified on Unity 7000.0.0a16, Entities 6.7.0, Burst 1.8.25, Ryzen 5 8500G (6C/12T, DDR5), 11 job workers. Numbers are medians of 5 fresh editor processes unless marked.

## Measuring honestly

- Editor batch runs compile Burst jobs with safety checks on by default. Set `BurstCompiler.Options.EnableBurstSafetyChecks = false`, `JobsUtility.JobDebuggerEnabled = false`, `NativeLeakDetection.Mode = NativeLeakDetectionMode.Disabled` at the top of the `-executeMethod`, before any job, and log them with every result. Tl 4M entities x4 kind fixture: 41.2 ms/tick [40.3-43.0] with them off (tl.unity 3b44b20) against about 52.9 ms with editor defaults on the same kind job (earlier harness): compare arms only under identical settings.
- Prove a generated job you cannot edit ran under Burst: call a `[BurstDiscard] static void Mark() { Hits = 1; }` (managed static) from a user method the job inlines (a feeder/Evaluate), and fail the run if `Hits != 0` after timing. Burst drops the call; a managed fallback sets it.
- Memory floor of a job: a Burst `IJobChunk` with read-only handles that sums exactly the bytes the job reads (enable bits, buffer headers and used elements, columns), timed the same way (schedule + complete, 32 steps). Tl kind job at 4M x4: touch 15.5 ms vs kind job 26.3 ms (59 %), so roughly 10 ms is compute above the floor; at 10k x150 it is 0.55 vs 2.15 ms (compute-bound).
- Bytes per entity: `archetype.ChunkCapacity` and `TypeManager.GetTypeInfo(type.TypeIndex).SizeInChunk` over `archetype.GetComponentTypes(Allocator.Temp)`; a buffer's SizeInChunk is header 16 B + inline capacity x element size. Tl scale archetype: 320 B/entity, 49 per chunk, of which `TimelineRequest` inline (8 x 16) is 128 B the kind job never reads.
- Before a Unity run, diff what a generator change emits: `dotnet Tl.Gen.Unity.Snapshot.dll <pkg>/Core <domain dir> <out> <AssemblyName>` emits the jobs for any domain folder in seconds (tl.unity `Tools~/Tl.Gen.Unity.Snapshot`).
