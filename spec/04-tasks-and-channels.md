# 4. Tasks and Channels

This section specifies Safe's concurrency model. Safe replaces the full Ada tasking facilities of 8652:2023 Sections 9.1 through 9.11 with a restricted model of static tasks communicating through typed, bounded channels. The model maps to the Jorvik tasking profile (8652:2023 Annex D.13) in the emitted Ada/SPARK code.

All 8652:2023 dynamic semantics for retained constructs (`delay`, `delay until`, the `Duration` type) apply except as modified below. All excluded Section 9 constructs are listed in Section 2 of this specification (see 2.1.7).

---

## 4.1 Task Declarations

### Syntax

4.1. The syntax for a task declaration is:

```
task_declaration ::=
    'task' identifier [ task_aspect_specification ] 'is'
    'begin'
        sequence_of_statements
    'end' identifier ';'

task_aspect_specification ::=
    'with' 'Priority' '=>' static_expression
```

The `sequence_of_statements` within the task body follows the grammar of Section 8, paragraph 8.7.

### Legality Rules

4.2. A task declaration shall appear only at package level -- that is, as a `package_declaration` within a `package_unit` (see Section 3 and Section 8, paragraph 8.2). A conforming implementation shall reject any task declaration that appears inside a subprogram body, block statement, or any other nested scope.

4.3. Each task declaration declares exactly one task. There are no task types, no task arrays, and no dynamic task creation. A conforming implementation shall reject any `task type` declaration (8652:2023 Section 9.1) or any use of an allocator to create a task.

4.4. The identifier following `end` shall match the identifier following `task`. A conforming implementation shall reject any task declaration where the identifiers do not match.

4.5. If the `task_aspect_specification` is present, the static expression following `Priority` shall be of an integer type and shall denote a value within the range `System.Any_Priority` (8652:2023 Section D.1). If the `task_aspect_specification` is omitted, the task receives the default priority defined by the implementation's Jorvik-profile runtime (8652:2023 Section D.1, paragraph 19).

4.6. The body of a task declaration (the `sequence_of_statements` between `begin` and `end`) constitutes a declarative and statement region. Declarations and statements may be interleaved within this region, following the same rules as subprogram bodies (see Section 3). The declaration-before-use rule applies: an entity declared within the task body is visible from its point of declaration to the end of the task body.

4.7. A task body may reference:
- (a) Variables and constants declared within the task body itself.
- (b) Package-level variables owned by that task (see 4.6, Task-Variable Ownership).
- (c) Package-level constants and types visible in the enclosing package.
- (d) Public declarations of with'd packages.
- (e) Channels declared at package level (for `send`, `receive`, `try_send`, `try_receive`, and `select` operations).

4.8. A task body may call subprograms declared in the enclosing package or in with'd packages, subject to the task-variable ownership rules (see 4.6).

### Static Semantics

4.9. A task declaration introduces a single named task into the enclosing package's declarative region. The task name is visible within the package but is not callable or referenceable as a value -- tasks are not first-class objects.

4.10. A task is not a type. No objects of a task type can be declared. No access values can designate tasks.

### Dynamic Semantics

4.11. Task startup ordering is specified in 4.7 (Task Startup).

4.12. When a task begins executing, its body's `sequence_of_statements` is executed. The task executes indefinitely until program termination. A conforming Safe program shall contain a non-terminating control structure (e.g., `loop ... end loop`) in every task body.

4.13. `return` shall not appear within a task body. A conforming implementation shall reject any `return` statement within a task body.

---

## 4.2 Channel Declarations

### Syntax

4.14. The syntax for a channel declaration is:

```
channel_declaration ::=
    [ 'public' ] 'channel' identifier ':' subtype_mark
        'capacity' static_expression ';'
```

### Legality Rules

4.15. A channel declaration shall appear only at package level -- that is, as a `package_declaration` within a `package_unit`. A conforming implementation shall reject any channel declaration that appears inside a subprogram body, task body, block statement, or any other nested scope.

4.16. The `subtype_mark` following the colon specifies the element type of the channel. The element type shall be a definite subtype (8652:2023 Section 3.3, paragraph 23/3). A conforming implementation shall reject any channel declaration whose element type is an indefinite subtype -- that is, an unconstrained array type, a type with unconstrained discriminants lacking defaults, or any other type for which the size is not statically determined.

4.17. The element type shall not be an access type. A conforming implementation shall reject any channel declaration whose element type is an access type or contains a component of an access type. This restriction ensures that values transmitted through channels are self-contained and do not create cross-task aliasing of heap objects.

4.18. The `static_expression` following `capacity` specifies the maximum number of elements the channel buffer can hold simultaneously. This expression shall be of an integer type and shall evaluate to a positive value (greater than zero) at compile time. A conforming implementation shall reject any channel declaration whose capacity expression is not static, is not of integer type, or evaluates to a value less than one.

4.19. A channel may be declared `public` to permit cross-package channel operations. A non-public channel is accessible only within the package in which it is declared.

4.20. Each channel declaration creates exactly one channel instance. There are no channel types, no channel arrays (beyond declaring multiple channels individually), and no dynamic channel creation.

### Static Semantics

4.21. A channel declaration introduces a named channel into the enclosing package's declarative region. The channel name may be used as the `channel_name` operand of `send`, `receive`, `try_send`, `try_receive`, and `select` statements.

4.22. A channel is not a variable and is not a type. A channel name shall not appear on the left-hand side of an assignment, shall not be passed as a parameter, and shall not be the target of an access value. Channel names may appear only in channel operation statements and `select` arms.

### Dynamic Semantics

4.23. A channel behaves as a bounded, first-in first-out (FIFO) queue. Elements are enqueued by `send` and `try_send` operations and dequeued by `receive` and `try_receive` operations, in the order they were enqueued.

4.24. The channel buffer is statically allocated. No dynamic memory allocation occurs for channel operations at runtime.

---

## 4.3 Channel Operations

### Syntax

4.25. The syntax for channel operations is:

```
send_statement ::=
    'send' channel_name ',' expression ';'

receive_statement ::=
    'receive' channel_name ',' name ';'

try_send_statement ::=
    'try_send' channel_name ',' expression ',' name ';'

try_receive_statement ::=
    'try_receive' channel_name ',' name ',' name ';'

channel_name ::=
    name
```

### Legality Rules

4.26. In a `send_statement`, the expression shall be of the channel's element type. A conforming implementation shall reject any `send` statement where the type of the expression does not match the channel's declared element type.

4.27. In a `receive_statement`, the `name` following the comma shall denote a variable of the channel's element type. A conforming implementation shall reject any `receive` statement where the target variable's type does not match the channel's declared element type.

4.28. In a `try_send_statement`, the expression (second operand) shall be of the channel's element type, and the `name` (third operand) shall denote a variable of type `Boolean`. A conforming implementation shall reject any `try_send` statement where these type constraints are not satisfied.

4.29. In a `try_receive_statement`, the first `name` (second operand) shall denote a variable of the channel's element type, and the second `name` (third operand) shall denote a variable of type `Boolean`. A conforming implementation shall reject any `try_receive` statement where these type constraints are not satisfied.

4.30. Channel operations are statements, not expressions. They do not produce values that can appear in an enclosing expression context.

4.31. The `channel_name` in a channel operation shall resolve to a channel declaration. A conforming implementation shall reject any channel operation whose first operand does not denote a declared channel.

### Dynamic Semantics

#### `send`

4.32. A `send` statement enqueues a copy of the value of the expression into the channel's buffer. If the channel buffer is full (the number of elements in the buffer equals the channel's capacity), the executing task blocks until space becomes available. The blocked task does not consume processor time while waiting (8652:2023 Section 9.5.3 entry call semantics apply to the underlying protected object entry call in the emitted Ada).

4.33. When space becomes available (because another task has dequeued an element), the blocked `send` completes: the value is enqueued and execution of the sending task resumes at the statement following the `send`.

4.34. A `send` operation is atomic with respect to the channel: no partial writes are observable. Either the entire element is enqueued or the sender remains blocked.

#### `receive`

4.35. A `receive` statement dequeues the oldest element from the channel's buffer and assigns it to the target variable. If the channel buffer is empty, the executing task blocks until an element becomes available.

4.36. When an element becomes available (because another task has enqueued an element), the blocked `receive` completes: the element is dequeued, assigned to the target variable, and execution of the receiving task resumes at the statement following the `receive`.

4.37. A `receive` operation is atomic with respect to the channel: no partial reads are observable. Either a complete element is dequeued and assigned or the receiver remains blocked.

#### `try_send`

4.38. A `try_send` statement attempts to enqueue a copy of the value into the channel's buffer without blocking. If the buffer is not full, the value is enqueued and the `Boolean` variable (third operand) is set to `True`. If the buffer is full, no enqueue occurs and the `Boolean` variable is set to `False`. The executing task never blocks on a `try_send`.

#### `try_receive`

4.39. A `try_receive` statement attempts to dequeue the oldest element from the channel's buffer without blocking. If the buffer is not empty, the element is dequeued, assigned to the target variable (second operand), and the `Boolean` variable (third operand) is set to `True`. If the buffer is empty, the target variable is not modified and the `Boolean` variable is set to `False`. The executing task never blocks on a `try_receive`.

### Interaction with Task Priorities

4.40. When multiple tasks are blocked on the same channel (either multiple senders on a full channel or multiple receivers on an empty channel), the task with the highest priority is unblocked first when the channel state changes. This follows from the ceiling priority protocol of the underlying protected object (8652:2023 Annex D.1 and D.3).

4.41. Channel operations respect the Jorvik-profile ceiling priority protocol. The ceiling priority of the protected object backing a channel is determined by the implementation as described in 4.9 (Implementation Requirements).

---

## 4.4 Select Statement

### Syntax

4.42. The syntax for a select statement is:

```
select_statement ::=
    'select'
        select_arm
    { 'or' select_arm }
    'end' 'select' ';'

select_arm ::=
    channel_arm
    | delay_arm

channel_arm ::=
    'when' identifier ':' subtype_mark 'from' channel_name '=>'
        sequence_of_statements

delay_arm ::=
    'delay' expression '=>'
        sequence_of_statements
```

### Legality Rules

4.43. A select statement shall contain at least one `channel_arm`. A conforming implementation shall reject any select statement that contains only `delay_arm` entries and no `channel_arm`.

4.44. Each `channel_arm` specifies a receive-only operation. A conforming implementation shall reject any select arm that attempts a send operation. Select on send is not permitted.

4.45. The `subtype_mark` in a `channel_arm` shall match the element type of the channel designated by `channel_name`. A conforming implementation shall reject any `channel_arm` where the declared subtype does not match the channel's element type.

4.46. The `identifier` introduced in a `channel_arm` (between `when` and the colon) declares a constant of the specified subtype. This constant is visible within the `sequence_of_statements` of that arm and nowhere else. Its value is the element dequeued from the channel when the arm is selected.

4.47. At most one `delay_arm` shall appear in a select statement. A conforming implementation shall reject any select statement containing more than one `delay_arm`.

4.48. The expression in a `delay_arm` shall be of type `Duration` (8652:2023 Section 9.6). It specifies the maximum time the select statement will wait before selecting the delay arm. The expression shall evaluate to a non-negative value; if the value is zero or negative at runtime, the delay arm is immediately eligible for selection if no channel arm is ready.

4.49. A select statement may appear in a task body, in a subprogram body, or in any statement context where compound statements are permitted.

### Dynamic Semantics

4.50. When a select statement is executed, the implementation evaluates the readiness of each channel arm in declaration order (top to bottom, first arm listed to last). A channel arm is ready if the designated channel's buffer is non-empty -- that is, a receive would not block.

4.51. If one or more channel arms are ready at the point of evaluation, the first ready arm (in declaration order) is selected. The element is dequeued from the designated channel, assigned to the arm's declared constant, and the arm's `sequence_of_statements` is executed. Execution then continues at the statement following `end select`.

4.52. If no channel arm is ready and no delay arm is present, the executing task blocks until at least one channel arm becomes ready. When a channel arm becomes ready, the first such arm in declaration order is selected, and execution proceeds as described in paragraph 4.51.

4.53. If no channel arm is ready and a delay arm is present, the executing task blocks until either (a) a channel arm becomes ready, or (b) the delay duration expires, whichever occurs first. If a channel arm becomes ready before the delay expires, execution proceeds as described in paragraph 4.51. If the delay expires before any channel arm becomes ready, the delay arm is selected and its `sequence_of_statements` is executed. Execution then continues at the statement following `end select`.

4.54. If multiple channels become ready simultaneously (that is, elements are enqueued on multiple channels between scheduling quanta such that more than one arm is ready when the implementation next evaluates readiness), the first ready arm in declaration order is selected. Arm ordering in source code determines selection priority. There is no random or round-robin selection.

4.55. A select statement executes at most one arm per invocation. After the selected arm's `sequence_of_statements` completes, no other arm is evaluated or executed.

### Starvation

4.56. A channel arm listed later in a select statement may be starved if earlier arms are continuously ready. This is by design -- declaration order provides explicit priority control over channel servicing. If fairness is required, the programmer shall use separate tasks for each channel, rotate through channels in application logic, or restructure the select arm ordering.

---

## 4.5 Delay Statements

### Syntax and Semantics

4.57. The `delay` statement and `delay until` statement are retained from 8652:2023 Section 9.6. Their syntax is:

```
delay_statement ::=
    'delay' expression ';'
    | 'delay' 'until' expression ';'
```

4.58. The `delay` form suspends the executing task for at least the specified duration (8652:2023 Section 9.6, paragraphs 20-21). The expression shall be of type `Duration`.

4.59. The `delay until` form suspends the executing task until at least the specified time (8652:2023 Section 9.6, paragraphs 23-24). The expression shall be of type `Ada.Real_Time.Time`. The package `Ada.Real_Time` is retained (see Annex A). `Ada.Calendar` is excluded because its operations raise exceptions.

4.60. Delay statements may appear in task bodies, subprogram bodies, and any statement context. They are not restricted to task bodies.

---

## 4.6 Task-Variable Ownership

This subsection specifies the no-shared-mutable-state rule, which is the fundamental concurrency safety invariant of the Safe language.

### Rule

4.61. Each package-level mutable variable shall be accessed by at most one task at runtime. The compiler shall determine, at compile time, which task (if any) owns each package-level mutable variable. A conforming implementation shall reject any program in which a package-level mutable variable is accessed by more than one task.

4.62. For the purposes of this rule, "accessed" means read or written, whether directly in the task body or transitively through any subprogram called from the task body.

### Ownership Determination Algorithm

4.63. The compiler shall determine task-variable ownership as follows:

(a) For each task declared in a package, the compiler computes the set of package-level mutable variables accessed by the task body. This set includes variables accessed directly by statements in the task body and variables accessed transitively through the call graph -- that is, variables accessed by any subprogram called from the task body, and by any subprogram called from those subprograms, recursively.

(b) This analysis is an extension of the `Global` analysis already performed for Bronze SPARK assurance (see Section 5). The compiler accumulates a read-set and write-set for each subprogram during compilation. The task's access set is the union of the access sets of the task body and all subprograms reachable from it in the call graph.

(c) For each package-level mutable variable `V`, the compiler determines the set of tasks that access `V`. If more than one task accesses `V`, the program is rejected with a diagnostic identifying the conflicting tasks and the variable.

(d) A variable is "owned" by a task if exactly one task accesses it. A variable not accessed by any task is unowned and remains accessible to non-task subprograms (subprograms that are not transitively called from any task body).

### Scope of the Rule

4.64. The ownership rule applies to package-level mutable variables -- that is, variables declared at package level that are not `constant`. Package-level constants, types, subtypes, and named numbers are not subject to this rule because they are immutable and may be safely read by any number of tasks.

4.65. Variables declared within a task body (local variables) are not subject to the ownership rule. Each task has its own stack; local variables are inherently task-private.

4.66. Variables declared within a subprogram body (local variables) are not subject to the ownership rule, even when the subprogram is called from a task body. Each call creates a new activation frame.

4.67. Channel names are not variables and are not subject to the ownership rule. Channels are communication endpoints accessible to any task, protected by the underlying synchronization mechanism.

### Transitivity Through the Call Graph

4.68. If subprogram `P` accesses a package-level mutable variable `V`, and task `T1` calls `P` (directly or transitively), then `T1` accesses `V` for the purposes of the ownership rule.

4.69. If subprogram `P` is called from two different tasks `T1` and `T2`, and `P` accesses a package-level mutable variable `V`, then both `T1` and `T2` access `V`, and the program shall be rejected.

4.70. A subprogram that accesses no package-level mutable variables (a pure function of its parameters and constants) may be called from any number of tasks without violating the ownership rule.

### Non-Task Subprograms

4.71. A subprogram that is not called from any task body (directly or transitively) may access any package-level mutable variable, subject to normal visibility rules. Such subprograms execute before tasks start (during package initialization) or are entry points called from the environment (see 4.7).

4.72. If a subprogram is called from at least one task body and also called from a non-task context (such as a package initializer or a public function called by client code), the ownership rule still applies: the subprogram's accessed variables are attributed to the calling task(s). If this causes a variable to be accessed by more than one task, the program shall be rejected. If the non-task context is the only caller, no ownership conflict arises.

### Diagnostic Requirements

4.73. When the compiler rejects a program due to a task-variable ownership violation, the diagnostic message shall identify: (a) the variable in question, (b) the tasks that access it, and (c) for each task, the call chain through which the variable is accessed.

---

## 4.7 Task Startup

4.74. All package-level initialization across all compilation units shall complete before any task begins executing. This is a sequencing guarantee.

4.75. Package initialization follows the elaboration order determined by the acyclic `with` dependency graph: if package A depends on package B (via a `with` clause), then B's package-level variable initializers complete before A's initializers begin. Within a package, variable initializers are evaluated in declaration order (top to bottom), as specified in Section 3.

4.76. After all package-level initialization is complete, all tasks declared across all packages begin executing. The relative startup order of tasks is not specified -- tasks may begin in any order. A program shall not depend on a particular task startup order.

4.77. This sequencing guarantee ensures that all package-level variables are fully initialized before any task accesses them. Combined with the ownership rule (4.6), this means each task begins executing with a consistent, fully-initialized view of its owned variables.

---

## 4.8 Task Non-Termination

4.78. A task executes indefinitely until program termination. Reaching the `end` of a task body is erroneous; conforming Safe programs shall contain a non-terminating control structure (e.g., `loop ... end loop`) in every task body. A conforming implementation shall reject any task body that does not contain a syntactically non-terminating loop.

4.79. This aligns with the Jorvik profile (8652:2023 Annex D.13), which includes `No_Task_Termination`. Safe tasks, like Ravenscar and Jorvik tasks, are designed to run for the lifetime of the program.

---

## 4.9 Implementation Requirements

This subsection specifies how Safe's task and channel constructs map to the emitted Ada 2022 / SPARK 2022 code under the Jorvik profile.

### Jorvik Profile

4.85. The emitted Ada shall include `pragma Profile (Jorvik)` (8652:2023 Annex D.13). If the Jorvik profile is not available for the target runtime, the implementation shall document the chosen alternative profile and any resulting restrictions, as specified in the Toolchain Baseline of this specification.

4.85a. The emitted Ada shall also include `pragma Partition_Elaboration_Policy (Sequential)` (8652:2023 §10.2.1). This pragma ensures that all library-level elaboration completes before any task activation occurs, enforcing the guarantee of §4.7 that all package-level initialization completes before any task begins executing. This is required by SPARK for programs that use tasks or protected objects under the Jorvik profile.

### Task Emission

4.86. Each Safe task declaration shall be emitted as an Ada task type with a single object (instance) of that type. The emitted task type shall include a `Priority` aspect if the Safe source specifies a priority.

4.87. For a Safe task declaration:

```
task Sensor_Reader with Priority => 10 is
begin
    -- body
end Sensor_Reader;
```

The emitted Ada shall be structurally equivalent to:

```ada
task type Sensor_Reader_Task with Priority => 10;

Sensor_Reader : Sensor_Reader_Task;

task body Sensor_Reader_Task is
begin
    -- translated body
end Sensor_Reader_Task;
```

4.88. The emitted task body shall include a `Global` aspect that references only the task's owned variables (as determined by the ownership analysis of 4.6) and channel-backing protected objects. This `Global` aspect enables GNATprove to verify data race freedom.

4.89. The naming convention for emitted task types shall be deterministic and documented. The implementation should use a consistent suffix (such as `_Task`) to distinguish the emitted task type from the task object.

### Channel Emission

4.90. Each Safe channel declaration shall be emitted as an Ada protected object with ceiling priority. The protected object shall contain:

(a) An internal bounded buffer, implemented as an array of the channel's element type with index range `0 .. Capacity - 1` (or an equivalent bounded structure).

(b) A count of elements currently in the buffer.

(c) A `Send` entry with a barrier that is open when the buffer is not full.

(d) A `Receive` entry with a barrier that is open when the buffer is not empty.

(e) A `Try_Send` procedure that attempts to enqueue without blocking.

(f) A `Try_Receive` procedure that attempts to dequeue without blocking.

4.91. For a Safe channel declaration:

```
channel Readings : Reading capacity 16;
```

The emitted Ada shall be structurally equivalent to:

```ada
protected Readings
    with Priority => Ceiling_Priority
is
    entry Send (Item : in Reading);
    entry Receive (Item : out Reading);
    procedure Try_Send (Item : in Reading; Success : out Boolean);
    procedure Try_Receive (Item : out Reading; Success : out Boolean);
private
    Buffer : array (0 .. 15) of Reading;
    Head   : Natural := 0;
    Count  : Natural := 0;
end Readings;
```

4.92. The `Ceiling_Priority` of the emitted protected object shall be the maximum of the priorities of all tasks that access the channel, as required by the ceiling priority protocol (8652:2023 Annex D.1 and D.3). The compiler shall compute this statically from the declared task priorities and the task-channel access graph.

4.93. If no task that accesses a channel has an explicit priority, the implementation shall assign the protected object a ceiling priority consistent with the Jorvik profile's default priority rules.

4.94. The internal buffer implementation shall be statically allocated. No dynamic memory allocation shall occur within the emitted protected object. The buffer size is fixed at the declared capacity.

### Channel Operation Emission

4.95. A Safe `send` statement shall be emitted as an entry call on the channel-backing protected object's `Send` entry:

```
send Readings, R;
```

emits as:

```ada
Readings.Send (R);
```

4.96. A Safe `receive` statement shall be emitted as an entry call on the channel-backing protected object's `Receive` entry:

```
receive Readings, R;
```

emits as:

```ada
Readings.Receive (R);
```

4.97. A Safe `try_send` statement shall be emitted as a procedure call on the channel-backing protected object's `Try_Send` procedure:

```
try_send Readings, R, Ok;
```

emits as:

```ada
Readings.Try_Send (R, Ok);
```

4.98. A Safe `try_receive` statement shall be emitted as a procedure call on the channel-backing protected object's `Try_Receive` procedure:

```
try_receive Readings, R, Ok;
```

emits as:

```ada
Readings.Try_Receive (R, Ok);
```

### Select Statement Emission

4.99. A Safe `select` statement shall be emitted as a pattern of conditional entry calls that implements the first-ready-wins semantics described in 4.4. The implementation shall test channel arms in declaration order.

4.100. For a select with channel arms and no delay arm, the emitted Ada shall poll each channel in order using `Try_Receive`, and if none succeeds, shall block on the first channel. The specific emission pattern is implementation-defined, provided that:

(a) The first-ready-wins selection semantics of paragraphs 4.50 through 4.54 are preserved.

(b) The emitted code is valid Jorvik-profile SPARK that GNATprove can analyze.

(c) No busy-waiting is introduced. If no arm is ready, the emitted code shall use an Ada blocking construct (entry call, delay, or equivalent).

4.101. For a select with a delay arm, the emitted Ada shall incorporate a `delay` statement or timed entry call that implements the timeout semantics of paragraph 4.53.

4.102. One valid emission pattern for a two-channel select with timeout:

```
select
    when Msg : Message from Incoming =>
        Process (Msg);
    or when Cmd : Command from Commands =>
        Handle (Cmd);
    or delay 1.0 =>
        Heartbeat;
end select;
```

is structurally equivalent to:

```ada
declare
    Msg     : Message;
    Cmd     : Command;
    Success : Boolean;
    Deadline : constant Ada.Real_Time.Time :=
        Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (1.0);
begin
    loop
        Incoming.Try_Receive (Msg, Success);
        if Success then
            Process (Msg);
            exit;
        end if;
        Commands.Try_Receive (Cmd, Success);
        if Success then
            Handle (Cmd);
            exit;
        end if;
        if Ada.Real_Time.Clock >= Deadline then
            Heartbeat;
            exit;
        end if;
        delay until Ada.Real_Time.Clock +
            Ada.Real_Time.Microseconds (100);
    end loop;
end;
```

The implementation may use alternative emission patterns (including GNAT-specific extensions for efficient conditional entry calls) provided the observable semantics match paragraphs 4.50 through 4.55.

### Task-Variable Ownership Emission

4.103. The compiler shall emit `Global` aspects on each task body in the emitted Ada that reference only the task's owned variables (by the analysis of 4.6) and channel-backing protected objects. This enables GNATprove to verify that no unprotected shared mutable state exists between tasks.

4.104. For a task that owns variable `Threshold` and accesses channel `Readings` (for receive) and channel `Alarms` (for send), the emitted `Global` aspect shall be structurally equivalent to:

```ada
task body Evaluator_Task
    with Global => (In_Out => (Threshold, Readings, Alarms))
is
    ...
end Evaluator_Task;
```

The specific form of the `Global` aspect (whether variables appear as `Input`, `Output`, or `In_Out`) shall reflect the actual read/write behavior of the task body.

---

## 4.10 Examples

### Example 1: Producer/Consumer

This example demonstrates basic channel communication between two tasks.

```
-- data_pipeline.safe

package Data_Pipeline is

    public type Sample is range 0 .. 1023;

    channel Samples : Sample capacity 32;

    task Producer with Priority => 10 is
    begin
        loop
            S : Sample := Read_Sensor;
            send Samples, S;
            delay 0.01;
        end loop;
    end Producer;

    task Consumer with Priority => 5 is
    begin
        loop
            S : Sample;
            receive Samples, S;
            Process (S);
        end loop;
    end Consumer;

    function Read_Sensor return Sample is separate;

    procedure Process (S : in Sample) is separate;

end Data_Pipeline;
```

The `Producer` task reads a sensor and sends samples through the `Samples` channel. The `Consumer` task receives samples and processes them. The channel capacity of 32 allows the producer to run ahead of the consumer by up to 32 samples before blocking. No mutable state is shared between the tasks.

### Example 2: Router/Worker

This example demonstrates a pattern where one task routes work to multiple workers via separate channels.

```
-- work_dispatch.safe

package Work_Dispatch is

    public type Job_Id is range 1 .. 10_000;

    public type Job is record
        Id       : Job_Id;
        Priority : Natural;
        Payload  : Integer;
    end record;

    public type Result is record
        Id    : Job_Id;
        Value : Integer;
    end record;

    channel Incoming_Jobs : Job capacity 64;
    channel Worker_A_Jobs : Job capacity 16;
    channel Worker_B_Jobs : Job capacity 16;
    channel Results       : Result capacity 64;

    task Router with Priority => 15 is
    begin
        loop
            J : Job;
            receive Incoming_Jobs, J;
            if J.Priority > 50 then
                send Worker_A_Jobs, J;
            else
                send Worker_B_Jobs, J;
            end if;
        end loop;
    end Router;

    task Worker_A with Priority => 10 is
    begin
        loop
            J : Job;
            receive Worker_A_Jobs, J;
            R : Result := (Id => J.Id, Value => J.Payload * 2);
            send Results, R;
        end loop;
    end Worker_A;

    task Worker_B with Priority => 5 is
    begin
        loop
            J : Job;
            receive Worker_B_Jobs, J;
            R : Result := (Id => J.Id, Value => J.Payload + 1);
            send Results, R;
        end loop;
    end Worker_B;

    public function Get_Result return Result is
    begin
        R : Result;
        receive Results, R;
        return R;
    end Get_Result;

end Work_Dispatch;
```

The `Router` task receives jobs from the `Incoming_Jobs` channel and dispatches them to `Worker_A` or `Worker_B` based on priority. Both workers post results to a shared `Results` channel. The `Get_Result` public function allows client packages to retrieve completed results. No mutable state is shared between any tasks.

### Example 3: Command/Response with Select and Timeout

This example demonstrates the `select` statement with multiple channel arms and a delay timeout, implementing a command processor that handles commands, status queries, and periodic heartbeats.

```
-- controller.safe

with Sensors;

package Controller is

    public type Command is (Start, Stop, Reset);

    public type Status_Query is (Get_State, Get_Count);

    public type Status_Response is record
        State : Command;
        Count : Natural;
    end record;

    channel Commands       : Command capacity 4;
    channel Status_Queries : Status_Query capacity 4;
    channel Status_Replies : Status_Response capacity 4;
    channel Heartbeats     : Boolean capacity 1;

    Current_State : Command := Stop;    -- owned by Controller_Task
    Op_Count      : Natural := 0;       -- owned by Controller_Task

    task Controller_Task with Priority => 10 is
    begin
        loop
            select
                when Cmd : Command from Commands =>
                    Current_State := Cmd;
                    Op_Count := Op_Count + 1;
                or when Q : Status_Query from Status_Queries =>
                    Resp : Status_Response :=
                        (State => Current_State, Count => Op_Count);
                    send Status_Replies, Resp;
                or delay 5.0 =>
                    send Heartbeats, True;
            end select;
        end loop;
    end Controller_Task;

    public procedure Send_Command (Cmd : in Command) is
    begin
        send Commands, Cmd;
    end Send_Command;

    public function Query_Status return Status_Response is
    begin
        send Status_Queries, Get_State;
        R : Status_Response;
        receive Status_Replies, R;
        return R;
    end Query_Status;

    public function Wait_Heartbeat return Boolean is
    begin
        H : Boolean;
        receive Heartbeats, H;
        return H;
    end Wait_Heartbeat;

end Controller;
```

The `Controller_Task` uses a `select` statement to multiplex across three sources: commands, status queries, and a 5-second timeout for heartbeat generation. The `Commands` channel arm is listed first, giving it priority over status queries when both are available simultaneously. The `Current_State` and `Op_Count` variables are owned exclusively by `Controller_Task` -- no other task or subprogram called from another task accesses them. The public subprograms `Send_Command`, `Query_Status`, and `Wait_Heartbeat` provide a channel-based API for client packages.

### Example 4: Non-Blocking with try_send and try_receive

This example demonstrates the non-blocking channel operations.

```
-- logger.safe

package Logger is

    public type Log_Level is (Debug, Info, Warning, Error);

    public type Log_Entry is record
        Level   : Log_Level;
        Code    : Integer;
    end record;

    channel Log_Queue : Log_Entry capacity 128;

    Dropped_Count : Natural := 0;  -- owned by Log_Writer

    task Log_Writer with Priority => 2 is
    begin
        loop
            Entry : Log_Entry;
            Ok    : Boolean;
            try_receive Log_Queue, Entry, Ok;
            if Ok then
                Write_To_Storage (Entry);
            else
                delay 0.1;
            end if;
        end loop;
    end Log_Writer;

    -- Called from any task; does not block the caller.
    public procedure Log (Level : in Log_Level; Code : in Integer) is
    begin
        E  : Log_Entry := (Level => Level, Code => Code);
        Ok : Boolean;
        try_send Log_Queue, E, Ok;
        -- If the queue is full, the entry is silently dropped.
        -- Counting drops requires shared state, which is
        -- architecturally avoided here.
    end Log;

    procedure Write_To_Storage (Entry : in Log_Entry) is separate;

end Logger;
```

The `Log` procedure uses `try_send` so that logging never blocks the calling task, even if the log queue is full. The `Log_Writer` task uses `try_receive` to poll for log entries, sleeping briefly when none are available. The `Dropped_Count` variable is owned by `Log_Writer`; no other task accesses it.
