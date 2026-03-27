# Annex A — Retained Library

**This section is normative.**

This annex walks through 8652:2023 Annex A (Predefined Language Environment) and states the Safe status of each library unit: retained, excluded, or modified. Annex B (Interface to Other Languages) is excluded in its entirety (D24).

---

## A.1 The Package Standard

1. **Status: RETAINED.**

2. Package `Standard` is retained. All declarations in `Standard` that correspond to retained language features are available:

   (a) Types `Boolean`, `Integer`, `Float`, `Character`, `Wide_Character`, `Wide_Wide_Character`, `String`, `Wide_String`, `Wide_Wide_String`, `Duration`.

   (b) Subtypes `Natural`, `Positive`.

   (c) Type `Universal_Integer`, `Universal_Real` (anonymous, as in 8652:2023).

3. Exception declarations in `Standard` (`Constraint_Error`, `Program_Error`, `Storage_Error`, `Tasking_Error`) are excluded. These names remain reserved but have no semantic meaning in Safe.

---

## A.2 The Package Ada

4. **Status: RETAINED.**

5. Package `Ada` is retained as the root of the predefined library hierarchy.

---

## A.3 Character Handling

### A.3.1 Ada.Characters, Ada.Wide_Characters, Ada.Wide_Wide_Characters

6. **Status: RETAINED.**

7. The packages `Ada.Characters`, `Ada.Wide_Characters`, and `Ada.Wide_Wide_Characters` are retained.

### A.3.2 Ada.Characters.Handling

8. **Status: RETAINED.**

9. `Ada.Characters.Handling` (8652:2023 §A.3.2) is retained. All functions in this package are total — no function raises an exception in 8652:2023:

   (a) Character classification functions (`Is_Letter`, `Is_Digit`, `Is_Upper_Case`, `Is_Lower_Case`, `Is_Basic`, `Is_Graphic`, `Is_Control`, `Is_Alphanumeric`, `Is_Special`, `Is_Hexadecimal_Digit`, `Is_ISO_646`) return `Boolean` for all inputs.

   (b) Character conversion functions (`To_Upper`, `To_Lower`, `To_Basic`) are defined for all `Character` and `String` values.

   (c) Cross-width functions (`To_Character`, `To_String` from wide types) use a `Substitute` parameter for non-representable characters; widening functions (`To_Wide_Character`, `To_Wide_String`) cannot fail. No exception path exists.

### A.3.3 Ada.Characters.Latin_1

12. **Status: RETAINED.**

13. Character constant declarations are retained.

### A.3.4 Ada.Characters.Conversions

14. **Status: RETAINED.**

15. `Ada.Characters.Conversions` (8652:2023 §A.3.4) is retained. All functions in this package are total — no function raises an exception in 8652:2023:

   (a) Classification functions (`Is_Character`, `Is_String`, `Is_Wide_Character`, `Is_Wide_String`) return `Boolean` for all inputs.

   (b) Widening conversions (`To_Wide_Character(Character)`, `To_Wide_Wide_Character(Character)`, `To_Wide_Wide_Character(Wide_Character)`, and their `String` variants) cannot fail.

   (c) Narrowing conversions (`To_Character`, `To_Wide_Character` from wider types, and their `String` variants) take a `Substitute` parameter and return it for non-representable characters. No exception path exists.

### A.3.5–A.3.6 Wide and Wide_Wide Character Handling

16. **Status: RETAINED.**

17. `Ada.Wide_Characters.Handling` (8652:2023 §A.3.5) and `Ada.Wide_Wide_Characters.Handling` (8652:2023 §A.3.6) are retained. These packages mirror `Ada.Characters.Handling` for `Wide_Character` and `Wide_Wide_Character` respectively. All functions are total: classification functions return `Boolean`, and conversion functions (`To_Upper`, `To_Lower`) are defined for all inputs. No function raises an exception.

---

## A.4 String Handling

### A.4.1 Ada.Strings

18. **Status: MODIFIED.**

19. The package `Ada.Strings` is modified: exception declarations (`Length_Error`, `Pattern_Error`, `Index_Error`, `Translation_Error`) are excluded. Enumeration types and constants (e.g., `Alignment`, `Truncation`, `Membership`, `Direction`, `Trim_End`) are retained.

### A.4.2 Ada.Strings.Maps

20. **Status: EXCLUDED.**

21. Rationale: depends on controlled types and exceptions.

### A.4.3 Ada.Strings.Fixed

22. **Status: EXCLUDED.**

23. Rationale: generic package; requires generics (D16) and raises exceptions.

### A.4.4 Ada.Strings.Bounded

24. **Status: EXCLUDED.**

25. Rationale: generic package; requires generics (D16).

### A.4.5 Ada.Strings.Unbounded

26. **Status: EXCLUDED.**

27. Rationale: generic package; requires generics, controlled types, and dynamic memory management with exceptions.

### A.4.6–A.4.8 String Maps, Wide_String, Wide_Wide_String Handling

28. **Status: EXCLUDED.**

29. Rationale: generic packages requiring generics (D16).

### A.4.9–A.4.12 String Hashing, Comparison, Encoding, Buffers

30. **Status: EXCLUDED.**

31. Rationale: generic packages, tagged types, or exceptions required. `Ada.Strings.Text_Buffers` (A.4.12) requires tagged types.

---

## A.5 The Numerics Packages

### A.5.1 Ada.Numerics.Elementary_Functions

32. **Status: EXCLUDED.**

33. Rationale: generic package (D16). The non-generic `Ada.Numerics.Elementary_Functions` instance for `Float` may be provided as an implementation extension, but is not required by this specification.

### A.5.2 Ada.Numerics.Float_Random, Ada.Numerics.Discrete_Random

34. **Status: EXCLUDED.**

35. Rationale: generic packages (D16). Random number generation is outside the scope of the safe language.

### A.5.3 Attributes of Floating Point Types

36. **Status: RETAINED.**

37. All floating-point attributes listed in A.5.3 are retained in dot notation (see Section 2, §2.5).

### A.5.4 Attributes of Fixed Point Types

38. **Status: RETAINED.**

39. All fixed-point attributes listed in A.5.4 are retained in dot notation.

### A.5.5–A.5.7 Big Numbers (Big_Integers, Big_Reals)

40. **Status: EXCLUDED.**

41. Rationale: requires tagged types, controlled types, and generics.

---

## A.6–A.13 Input-Output

42. **Status: EXCLUDED in their entirety.**

43. This includes:

   (a) `Ada.Sequential_IO` (A.8.1) — generic package.

   (b) `Ada.Direct_IO` (A.8.4) — generic package.

   (c) `Ada.Storage_IO` (A.9) — generic package.

   (d) `Ada.Text_IO` (A.10) — raises exceptions; uses controlled types for file management.

   (e) `Ada.Wide_Text_IO` (A.11) — same rationale.

   (f) `Ada.Streams.Stream_IO` (A.12.1) — requires streams, tagged types.

   (g) `Ada.Exceptions_In_IO` (A.13) — requires exceptions.

44. Rationale: all I/O packages in the standard library depend on exceptions for error reporting (End_Error, Status_Error, Mode_Error, Name_Error, Use_Error) and many require generics. I/O is outside the scope of the safe language; a future system sublanguage may provide I/O facilities.

45. The built-in `print` statement does not change this status. `print` is a
language-defined statement lowered through implementation-generated support
code; it is not a retained Safe-source admission of `Ada.Text_IO`.

---

## A.14 File Sharing

45. **Status: EXCLUDED.**

46. Rationale: depends on I/O packages, which are excluded.

---

## A.15 Ada.Command_Line

47. **Status: EXCLUDED.**

48. Rationale: raises `Constraint_Error` on invalid argument indices; requires exceptions.

---

## A.16 Ada.Directories

49. **Status: EXCLUDED.**

50. Rationale: raises exceptions; requires controlled types for search operations.

---

## A.17 Ada.Environment_Variables

51. **Status: EXCLUDED.**

52. Rationale: raises exceptions.

---

## A.18 Containers

53. **Status: EXCLUDED in their entirety.**

54. All container packages (`Ada.Containers.Vectors`, `Ada.Containers.Doubly_Linked_Lists`, `Ada.Containers.Hashed_Maps`, `Ada.Containers.Ordered_Maps`, `Ada.Containers.Hashed_Sets`, `Ada.Containers.Ordered_Sets`, `Ada.Containers.Multiway_Trees`, and their bounded and indefinite variants) are excluded.

55. Rationale: all container packages are generic (D16), use tagged types for iteration, use controlled types for automatic memory management, and raise exceptions on constraint violations. Safe provides access types with ownership for dynamic data structures (D17).

---

## Additional Predefined Packages

### System (8652:2023 §13.7)

56. **Status: RETAINED.**

57. Package `System` is retained. `System.Storage_Elements` (§13.7.1) is retained. `System.Address_To_Access_Conversions` (§13.7.2) is excluded (unsafe conversion).

### Ada.Calendar (8652:2023 §9.6)

58. **Status: EXCLUDED.**

59. Rationale: `Ada.Calendar` raises `Time_Error` on invalid time values; requires exceptions. The `delay until` statement is also excluded (Section 2, paragraph 60), so no language-defined time type is required.

### Ada.Real_Time (Annex D)

60. **Status: EXCLUDED.**

61. Rationale: Annex D is excluded except for task priorities (Section 2, §2.1.13).

### Ada.Task_Identification (8652:2023 §C.7.1)

62. **Status: EXCLUDED.**

63. Rationale: requires Ada tasking model, which is excluded.

### Ada.Synchronous_Task_Control (8652:2023 §D.10)

64. **Status: EXCLUDED.**

65. Rationale: channels replace suspension objects.

### Ada.Finalization (8652:2023 §7.6)

66. **Status: EXCLUDED.**

67. Rationale: controlled types are excluded (Section 2, §2.1.2, paragraph 12).

### Ada.Unchecked_Conversion (8652:2023 §13.9)

68. **Status: EXCLUDED.**

69. Rationale: unsafe capability (Section 2, §2.1.12, paragraph 78).

### Ada.Unchecked_Deallocation (8652:2023 §13.11.2)

70. **Status: EXCLUDED.**

71. Rationale: deallocation is automatic through ownership model (Section 2, §2.3.5).

### Ada.Tags (8652:2023 §3.9)

72. **Status: EXCLUDED.**

73. Rationale: tagged types are excluded (D18).

### Ada.Exceptions (8652:2023 §11.4.1)

74. **Status: EXCLUDED.**

75. Rationale: exceptions are excluded (D14).

---

## Summary Table

76. The following table provides a quick reference:

| Library Unit | Status | Reason for Exclusion |
|-------------|--------|---------------------|
| Standard | Retained | Core language types |
| Ada | Retained | Root package |
| Ada.Characters.* | Retained | All functions are total; no exception paths |
| Ada.Strings | Modified | Exceptions excluded; enumerations retained |
| Ada.Strings.Fixed/Bounded/Unbounded | Excluded | Generic; exceptions |
| Ada.Numerics.Elementary_Functions | Excluded | Generic |
| Ada.Numerics.*_Random | Excluded | Generic |
| Ada.Sequential_IO / Direct_IO | Excluded | Generic; exceptions |
| Ada.Text_IO | Excluded | Exceptions; controlled types |
| Ada.Wide_Text_IO | Excluded | Exceptions; controlled types |
| Ada.Streams.* | Excluded | Tagged types; controlled types |
| Ada.Command_Line | Excluded | Exceptions |
| Ada.Directories | Excluded | Exceptions; controlled types |
| Ada.Environment_Variables | Excluded | Exceptions |
| Ada.Containers.* | Excluded | Generic; tagged; controlled; exceptions |
| System | Retained | Core system package |
| System.Storage_Elements | Retained | Address arithmetic |
| System.Address_To_Access_Conversions | Excluded | Unsafe conversion |
| Ada.Calendar | Excluded | Exceptions |
| Ada.Real_Time | Excluded | Annex D excluded |
| Ada.Task_Identification | Excluded | Ada tasking excluded |
| Ada.Finalization | Excluded | Controlled types excluded |
| Ada.Unchecked_Conversion | Excluded | Unsafe |
| Ada.Unchecked_Deallocation | Excluded | Automatic deallocation via ownership |
| Ada.Tags | Excluded | Tagged types excluded |
| Ada.Exceptions | Excluded | Exceptions excluded |
