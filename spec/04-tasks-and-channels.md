# Section 4 — Tasks and Channels

**This section is normative.**

This section specifies Safe's concurrency model. Safe provides concurrency through static tasks and typed channels as first-class language constructs. Tasks are declared at package level and create exactly one task each. Channels are typed, bounded-capacity, blocking FIFO queues. Tasks communicate exclusively through channels — no shared mutable state between tasks.

---

## 4.1 Task Declarations

### Syntax

1. A task is declared at the top level of a package:

```
task_declaration ::=
    'task' defining_identifier
        [ 'with' 'priority' '=' static_expression ]
        [ [ ',' ] task_channel_clause { [ ',' ] task_channel_clause } ]
        indented_task_body

task_channel_clause ::=
    'sends' channel_name { ',' channel_name }
  | 'receives' channel_name { ',' channel_name }

indented_task_body ::=
    INDENT
        { basic_declaration }
        { statement_item }
    DEDENT
```

### Legality Rules

2. A task declaration shall appear only at the top level of a package (as a `package_item`). A conforming implementation shall reject any task declaration appearing within a subprogram body, block statement, or nested scope.

3. Each task declaration creates exactly one task. There are no task types, no dynamic task creation, no task arrays.

4. Task bodies use indentation rather than legacy `begin` / `end` delimiters. A conforming implementation shall reject legacy explicit closing keywords in task declarations.

5. If a `priority` aspect is specified, the static expression shall evaluate to a value in the range `System.Any_Priority`. A conforming implementation shall reject a priority value outside this range.

6. A task declaration shall not bear the `public` keyword. Tasks are execution entities internal to the package.

7. Task declarations shall not be nested. A task body shall not contain another task declaration. A conforming implementation shall reject any task declaration appearing within a task body.

7a. Each `channel_name` named in a task `sends` or `receives` clause shall denote a visible channel. A conforming implementation shall reject any unknown name in a task channel-direction clause.

7b. Within a single direction (`sends` or `receives`), a channel shall be listed at most once. A conforming implementation shall reject duplicate channels within the same direction. The same channel may appear in both `sends` and `receives`.

7c. If a task declaration includes a `sends` clause, every `send` and `try_send` operation reachable from that task body, whether direct or through transitive subprogram calls, shall target a channel listed in that `sends` clause. If no `sends` clause is present, send-like operations are unrestricted.

7d. If a task declaration includes a `receives` clause, every `receive`, `try_receive`, and `select` channel arm reachable from that task body, whether direct or through transitive subprogram calls, shall target a channel listed in that `receives` clause. If no `receives` clause is present, receive-like operations are unrestricted.

7e. Cross-package enforcement of task channel-direction clauses shall use the dependency interface channel-access summaries described in Section 3, §3.3.1(i). A conforming implementation shall accept legacy flat summaries that list only `channels`, but if a constrained task reaches an imported subprogram whose legacy summary names a channel that is not admitted by every constrained direction the task declares, the implementation shall reject the call and require regenerated provider interfaces with directional `sends` / `receives` summaries.

### Static Semantics

8. The `defining_identifier` of a task declaration introduces a name in the enclosing package's declarative region. This name is not a type name and cannot be used as a type mark.

9. If no `priority` is specified, the task has the default priority defined by the implementation. The default priority shall be documented by the implementation.

### Dynamic Semantics

10. Each task declaration creates a single task that begins execution after all package-level initialisation completes (see §4.7).

11. The task executes its indented body as an independent thread of control. Scheduling among tasks is preemptive priority-based. Tasks of equal priority are scheduled in implementation-defined order.

---

## 4.2 Channel Declarations

### Syntax

12. A channel is a typed, bounded FIFO queue declared at the top level of a package:

```
channel_declaration ::=
    [ 'public' ] 'channel' defining_identifier ':' subtype_mark
        'capacity' static_expression ';'
```

### Legality Rules

13. A channel declaration shall appear only at the top level of a package. A conforming implementation shall reject any channel declaration appearing within a subprogram body, task body, or nested scope.

14. The element type (`subtype_mark`) shall be a definite type (not an unconstrained array or unconstrained discriminated type). A channel element type shall not be an access type, and shall not be a composite type that contains an access-type subcomponent. A conforming implementation shall reject a channel whose element type is indefinite or access-bearing.

15. The capacity (`static_expression`) shall evaluate to a positive integer. A conforming implementation shall reject a channel with a capacity less than 1.

16. A channel may bear the `public` keyword to make it visible to client packages for cross-package communication.

### Static Semantics

17. A channel declaration introduces a name in the enclosing package's declarative region. This name denotes a channel object, not a type.

18. The storage required for a channel is bounded: element size multiplied by capacity, plus implementation-defined overhead for the queue structure. The allocation strategy (static, pre-allocated, or other) is implementation-defined.

### Dynamic Semantics

19. A channel is initially empty. Its lifetime is the lifetime of the enclosing package (i.e., the lifetime of the program, since packages are not deallocated).

20. A channel is a FIFO queue: elements are dequeued in the order they were enqueued.

21. **Ceiling priority.** When the implementation maps channels to underlying synchronisation mechanisms, it shall assign a ceiling priority to each channel. The ceiling priority of a channel shall be at least the maximum of the priorities of all tasks that access that channel (directly or transitively through subprogram calls). This is required to prevent priority inversion.

21a. **Ceiling computation across packages.** A conforming implementation shall compute each channel's ceiling priority from the priorities of all tasks that access the channel, using channel-access summaries from dependency interface information (Section 3, §3.3.1(i)) for cross-package calls. Specifically:

   (a) For each public subprogram in a provider package, the dependency interface information includes a conservative summary of which channels the subprogram accesses (directly or transitively).

   (b) When a task in a client package calls such a subprogram, the implementation adds the task's priority to the set of priorities considered for each channel listed in the summary.

   (c) The ceiling priority computation shall be completable from the compilation unit's source plus its direct and transitive dependency interface information, without access to dependency source code. This mirrors the requirement for task-variable ownership checking (Section 4, §4.5, paragraph 47).

   (d) A conservative over-approximation of channel access (listing channels that may not actually be accessed on every path) is permitted — it may raise ceilings above the necessary minimum but does not compromise priority inversion prevention.

---

## 4.3 Channel Operations

### Syntax

22.

```
send_statement ::=
    'send' channel_name ',' expression ';'

receive_statement ::=
    'receive' channel_name ',' receive_target ';'

receive_target ::=
    name | defining_identifier ':' subtype_indication

try_send_statement ::=
    'try_send' channel_name ',' expression ',' name ';'

try_receive_statement ::=
    'try_receive' channel_name ',' receive_target ',' name ';'
```

### Legality Rules

23. The expression in a `send` or `try_send` shall be of the channel's element type or a subtype thereof.

24. The `name` in a `receive` or `try_receive` shall denote a variable of the channel's element type or a subtype thereof.

24a. In the `defining_identifier ':' subtype_indication` form of `receive` or `try_receive`, the subtype indication shall match the channel element type or a subtype thereof. The defining identifier declares a new variable scoped to the remainder of the enclosing statement sequence, exactly as if an equivalent local variable declaration had appeared immediately before the channel operation. Normal shadowing and redeclaration rules apply.

25. The final `name` in `try_send` and `try_receive` shall denote a variable of type `boolean`.

26. Channel operations may appear in subprogram bodies, task bodies, and other statement contexts. They shall not appear at the package level (no package-level statements, §3.2.4).

### Dynamic Semantics

27. **`send Ch, Value;`** — Enqueue `Value` into channel `Ch`. If `Ch` is full (number of elements equals capacity), the current task blocks until space becomes available. The blocking is on the current task only, not the entire program. The expression `Value` is evaluated before the enqueue (and before blocking, if the channel is full). Once space becomes available, the evaluated value is enqueued.

27a. **Copy-only enqueue.** Because channel element types exclude access types and composite types containing access-type subcomponents (Section 4, §4.2, paragraph 14), `send` never transfers ownership of a designated object through the channel. The value enqueued is a copy of the evaluated payload.

28. **`receive Ch, Variable;`** — Dequeue the front element of channel `Ch` into `Variable`. If `Ch` is empty, the current task blocks until an element becomes available. In the scoped-binding form `receive Ch, Name : T;`, the implementation first declares `Name` and then performs the receive into that new variable.

28a. **Copy-only dequeue.** Because channel element types exclude access types and composite types containing access-type subcomponents (Section 4, §4.2, paragraph 14), `receive` never transfers ownership of a designated object through the channel. The dequeued element is copied into `Variable`.

29. **`try_send ch, value, success;`** — Attempt to enqueue `value` into channel `ch` without blocking. The operation is performed atomically: the implementation acquires the channel, evaluates the channel's fullness, and if not full, enqueues `value` and sets `success` to `true`. If `ch` is full, no element is enqueued and `success` is set to `false`.

29a. **Copy-only-on-success.** Because channel element types exclude access-bearing elements (Section 4, §4.2, paragraph 14), `try_send` never conditionally transfers ownership. When `success` is `true`, a copy of `value` is enqueued. When `success` is `false`, no element is enqueued and the source expression's ownership state is unchanged.

29b. **Evaluation order for `try_send`.** The expression `value` is evaluated before the atomic fullness check. If the channel is not full, the already-evaluated value is enqueued. If the channel is full, the evaluated value is discarded. No ownership transfer occurs because access-bearing channel element types are illegal.

30. **`try_receive ch, variable, success;`** — Attempt to dequeue the front element of channel `ch` without blocking. If `ch` is not empty, the element is dequeued into `variable` and `success` is set to `true`. If `ch` is empty, `variable` is unchanged and `success` is set to `false`. In the scoped-binding form `try_receive ch, name : T, success;`, the implementation first declares `name` and default-initializes it as a value of type `T`; if the receive fails, that default value remains in place. Because channel element types exclude access-bearing values (Section 4, §4.2, paragraph 14), `try_receive` never transfers ownership through the channel.

31. Channel operations are atomic with respect to other channel operations on the same channel. The implementation shall ensure that concurrent `send` and `receive` operations on the same channel do not corrupt the channel state.

31a. **Channel non-ownership invariant.** Because channel element types exclude access types and composite types containing access-type subcomponents (Section 4, §4.2, paragraph 14), queued channel elements never own designated objects. Channel state therefore cannot alias task-owned heap objects through channel storage.

---

## 4.4 Select Statement

### Syntax

32.

```
select_statement ::=
    'select'
        indented_select_arm
    { 'or'
        indented_select_arm }

indented_select_arm ::=
    INDENT
        select_arm
    DEDENT

select_arm ::=
    channel_arm | delay_arm

channel_arm ::=
    'when' defining_identifier ':' subtype_mark 'from' channel_name
        indented_statement_suite

delay_arm ::=
    'delay' expression
        indented_statement_suite
```

### Legality Rules

33. A `select` statement shall contain at least one `channel_arm`.

34. At most one `delay_arm` may appear in a `select` statement. A conforming implementation shall reject a `select` with more than one `delay_arm`.

35. Only receive operations appear in `select` arms, not send. A conforming implementation shall reject any `select` arm that attempts a send operation.

36. The `subtype_mark` in a `channel_arm` shall match the element type of the named channel.

37. The `defining_identifier` in a `channel_arm` introduces a new variable, scoped to the statements of that arm.

38. The `expression` in a `delay_arm` shall be of type `duration` or a type convertible to `duration`.

### Dynamic Semantics

39. **Arm selection semantics.** When the `select` statement is evaluated, the implementation tests each arm in declaration order (top to bottom). The first arm whose channel has data available is selected. If no channel arm is ready and a delay arm is present, the implementation waits until either a channel arm becomes ready or the delay expires, whichever occurs first.

40. If the delay expires before any channel arm becomes ready, the delay arm is selected.

41. If multiple channels become ready simultaneously (e.g., data arrives on two channels between scheduling quanta), the first listed channel arm is selected. This is deterministic — arm ordering in source code determines priority. There is no random selection.

42. If no channel arm is ready and no delay arm is present, the `select` blocks until one channel arm becomes ready.

43. Once an arm is selected, its `sequence_of_statements` is executed. For a channel arm, the received value is bound to the `defining_identifier` before the statements execute. Channel-arm binding copies the dequeued element; it does not establish ownership of a designated object through the channel.

44. **Starvation.** A channel whose arm is listed later in a `select` may be starved if earlier arms are always ready. This is by design — it gives the programmer explicit priority control via declaration order.

---

## 4.5 Task-Variable Ownership

### Legality Rules

45. **No shared mutable state between tasks.** Each package-level variable shall be accessed by at most one task. The implementation shall verify this at compile time. A conforming implementation shall reject any program where a package-level variable is accessed by more than one task.

46. **Access determination.** A task accesses a package-level variable if:

   (a) The variable appears directly in the task body.

   (b) The variable appears in a subprogram called (directly or transitively) from the task body.

47. **Cross-package transitivity.** For subprograms in `with`'d packages, the implementation shall use the effect summaries from dependency interface information (Section 3, §3.3.1(d)) to determine which package-level variables are accessed. The ownership check shall be completable from the compilation unit's source plus its direct and transitive dependency interface information, without access to dependency source code.

48. **Variables not accessed by any task** remain accessible to non-task subprograms (package-level initialisation expressions and subprograms not called from any task body).

49. **Subprograms callable from multiple tasks.** A subprogram shall not access any package-level variable if it is callable from more than one task. A conforming implementation shall reject any subprogram that accesses a package-level variable and is callable from multiple task bodies.

50. **Channels are not variables.** Channel operations do not constitute "access to a package-level variable" for the purposes of this ownership rule. Channels are the designated mechanism for inter-task communication.

### Static Semantics

51. The task-variable ownership analysis produces a mapping from each package-level variable to at most one task. This mapping is a static property of the program.

52. For mutually recursive subprograms, the implementation may use a fixed-point computation to determine the complete set of variables accessed.

---

## 4.6 Non-Termination Legality Rule

### Legality Rules

53. Tasks shall not terminate. A conforming implementation shall enforce the following constraints on every task body:

   (a) The outermost statement of the task body's executable region shall be an unconditional `loop` statement (`loop ...`). Declarations may precede the loop.

   (b) A `return` statement shall not appear anywhere within a task body. A conforming implementation shall reject any `return` statement within a task body.

   (c) No `exit` statement within the task body shall name or otherwise target the outermost loop. `exit` statements targeting inner loops within the task body are permitted.

54. These constraints are syntactic restrictions checkable without control-flow analysis or whole-program analysis.

55. Some theoretically non-terminating forms (e.g., `while true ...`) are not accepted. The unconditional `loop` form is trivially verifiable by any implementation.

---

## 4.7 Task Startup

### Dynamic Semantics

56. All package-level declarations and initialisations across all compilation units complete before any task begins executing. This is a language-level sequencing guarantee.

57. The order of package initialisation across compilation units is a topological sort of the `with` dependency graph (Section 3, §3.4.2).

58. Once all initialisation is complete, all tasks begin execution. The order in which tasks are activated relative to each other is implementation-defined.

59. **Informative note.** When targeting Ada/SPARK tasking under Ravenscar or Jorvik profile restrictions, `pragma Partition_Elaboration_Policy(Sequential)` is the standard mechanism for ensuring library-level task activation is deferred until all library units are elaborated. The normative requirement is the language-level guarantee stated in paragraph 56; the mechanism for achieving it is implementation-defined.

---

## 4.8 Examples

### 4.8.1 Example: Producer/Consumer

**Conforming Example.**

```safe
-- pipeline.safe

package pipeline

    public subtype measurement is integer (0 to 65535);

    channel raw_data : measurement capacity 16;
    channel processed : measurement capacity 8;

    task producer with priority = 10

        loop
            sample : measurement = read_sensor;
            send raw_data, sample;
            delay 0.01;

    task consumer with priority = 5

        loop
            m : measurement;
            receive raw_data, m;
            result : measurement = process (m);
            send processed, result;
            -- D27 proof: all types match; no runtime errors

    function read_sensor returns measurement is separate;

    function process (m : measurement) returns measurement

        return (m + 1) / 2;
        -- D27 Rule 1: max (65535+1)/2 = 32768
        -- D27 Rule 3(b): literal 2 is static nonzero
        -- D27 proof: result in 0..65535

    public function get_result returns measurement
        r : measurement;
        receive processed, r;
        return r;

```

### 4.8.2 Example: Router/Worker

**Conforming Example.**

```safe
-- router.safe

package router

    public subtype job_id is integer (1 to 1000);
    public type job is record
        id   : job_id;
        data : integer;

    public type result is record
        id    : job_id;
        value : integer;

    channel jobs_a : job capacity 4;
    channel jobs_b : job capacity 4;
    public channel results : result capacity 8;

    task dispatcher with priority = 8
        count : job_id = 1;

        loop
            j : job = (id = count, data = integer (count) * 10);
            -- D27 proof: count * 10 fits within signed 64-bit integer range
            ok : boolean;
            try_send jobs_a, j, ok;
            if not ok
                send jobs_b, j;
            count = (if count == job_id.last then job_id.first else count + 1);

    task worker_a with priority = 5

        loop
            j : job;
            receive jobs_a, j;
            send results, (id = j.id, value = j.data + 1);
            -- D27 proof: j.data + 1 is rejected unless it is provably within signed 64-bit integer range

    task worker_b with priority = 5

        loop
            j : job;
            receive jobs_b, j;
            send results, (id = j.id, value = j.data + 2);

```

### 4.8.3 Example: Command/Response with Select

**Conforming Example.**

```safe
-- controller.safe

package controller

    public type command is (start, stop, reset);
    public type status  is (running, stopped, error);

    public channel commands : command capacity 4;
    public channel responses : status capacity 4;
    channel heartbeats : boolean capacity 1;

    current_state : status = stopped;  -- owned by control_loop

    task control_loop with priority = 10

        loop
            select
                when cmd : command from commands
                    case cmd
                        when start
                            current_state = running;
                            send responses, running;
                        when stop
                            current_state = stopped;
                            send responses, stopped;
                        when reset
                            current_state = stopped;
                            send responses, stopped;
                or
                    delay 5.0
                        send heartbeats, true;

    public function get_status returns status

        return current_state;
    -- Note: this is callable only from the task that owns current_state
    -- or from non-task context during initialisation.
    -- D27 proof: status is an enumeration; no runtime error possible.

```

---

## 4.9 Relationship to 8652:2023

60. The following table summarises how Safe's concurrency model relates to 8652:2023 Section 9:

| 8652:2023 Feature | Safe Status |
|-------------------|-------------|
| Task types (§9.1) | Excluded — static task declarations instead |
| Task activation (§9.2) | Modified — all init completes first |
| Task dependence/termination (§9.3) | Modified — tasks shall not terminate |
| Protected types (§9.4) | Excluded as user-visible; may be used internally |
| Entries and accept (§9.5.2) | Excluded — channels instead |
| Entry calls (§9.5.3) | Excluded |
| Requeue (§9.5.4) | Excluded |
| Delay statements (§9.6) | Retained |
| Select statements (§9.7) | Replaced by Safe's channel-based select |
| Abort (§9.8) | Excluded |
| Task/entry attributes (§9.9) | Excluded |
| Shared variables (§9.10) | Superseded by task-variable ownership |
