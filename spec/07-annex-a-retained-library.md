# 7a. Annex A -- Retained Library

This section walks through 8652:2023 Annex A (Predefined Language Environment) and classifies every library unit as **RETAINED**, **EXCLUDED**, or **MODIFIED**. For each exclusion, the rationale is stated. For each modification, the nature of the change is described.

The classification follows from the language restrictions specified in Section 2. The principal exclusion drivers are:

- **Generics (D16):** All generic packages and generic library units are excluded.
- **Exceptions (D14):** Packages whose primary purpose is exception propagation or whose interface is dominated by exception-raising operations are excluded or modified.
- **Tagged types (D18):** Packages requiring tagged types, dispatching, or class-wide types are excluded.
- **Controlled types (Section 2, 7.6):** Packages requiring `Ada.Finalization` are excluded.
- **Streams (Section 2, 13.13):** Stream-oriented packages and stream attributes are excluded.
- **Full tasking (D15):** Full Ada tasking packages are excluded; `Ada.Real_Time` is retained for `delay until`.
- **Foreign interface (D24):** Annex B in its entirety is excluded.

All paragraph numbers in this section are local to this annex.

---

## 7a.1 Annex A -- Predefined Language Environment (Overview)

1. 8652:2023 Annex A defines the predefined language environment: the library units that a conforming Ada implementation shall provide. Safe retains a subset of these library units, consistent with the restrictions specified in Section 2.

2. A conforming Safe implementation shall provide the library units classified as RETAINED or MODIFIED in this annex. A conforming Safe implementation shall not make available to Safe programs any library unit classified as EXCLUDED, unless that unit is accessed through the emitted Ada layer outside the scope of this specification.

3. Where a retained library unit contains subprograms that raise language-defined exceptions, the Safe implementation shall document the behavior on error conditions. Since exceptions are excluded (D14), operations that would raise exceptions in Ada instead invoke the runtime abort handler with a diagnostic message, unless the Safe program's type rules (D27) make the error condition statically unreachable.

---

## 7a.2 A.1 -- The Package Standard

4. **Status: RETAINED.**

5. The package `Standard` (8652:2023 A.1) is retained. It defines the predefined types `Boolean`, `Integer`, `Float`, `Character`, `Wide_Character`, `Wide_Wide_Character`, `String`, `Wide_String`, `Wide_Wide_String`, `Duration`, and the predefined subtypes `Natural`, `Positive`, and `Negative`.

6. The predefined exceptions `Constraint_Error`, `Program_Error`, `Storage_Error`, and `Tasking_Error` are part of `Standard` but are not raisable in Safe programs. Their declarations exist in the emitted Ada for compatibility; a Safe program shall not reference these names. Runtime check failures that would raise `Constraint_Error` in Ada are statically prevented by D27 rules or result in invocation of the runtime abort handler.

---

## 7a.3 A.2 -- The Package Ada

7. **Status: RETAINED.**

8. The package `Ada` (8652:2023 A.2) is the root package for the Ada predefined library hierarchy. It is a pure package with no declarations of its own and is retained as the namespace root.

---

## 7a.4 A.3 -- Character Handling

### 7a.4.1 A.3.1 -- The Packages Characters, Wide_Characters, and Wide_Wide_Characters

9. **Status: RETAINED.**

10. The packages `Ada.Characters`, `Ada.Wide_Characters`, and `Ada.Wide_Wide_Characters` (8652:2023 A.3.1) are pure namespace packages with no declarations of their own. They are retained as namespace roots for their child packages.

### 7a.4.2 A.3.2 -- The Package Characters.Handling

11. **Status: RETAINED.**

12. The package `Ada.Characters.Handling` (8652:2023 A.3.2) provides character classification functions (`Is_Letter`, `Is_Digit`, `Is_Alphanumeric`, etc.) and case conversion functions (`To_Upper`, `To_Lower`). All operations are pure functions on `Character` values. This package does not use generics, tagged types, or exceptions in its interface, and is retained without modification.

### 7a.4.3 A.3.3 -- The Package Characters.Latin_1

13. **Status: RETAINED.**

14. The package `Ada.Characters.Latin_1` (8652:2023 A.3.3) provides named constants for the Latin-1 character set (e.g., `NUL`, `BEL`, `LF`, `CR`, `Space`). This package is a pure constant-only package and is retained without modification.

### 7a.4.4 A.3.4 -- The Package Characters.Conversions

15. **Status: RETAINED.**

16. The package `Ada.Characters.Conversions` (8652:2023 A.3.4) provides conversion functions between `Character`, `Wide_Character`, and `Wide_Wide_Character`. All operations are pure functions. This package is retained without modification.

### 7a.4.5 A.3.5 -- The Package Wide_Characters.Handling

17. **Status: RETAINED.**

18. The package `Ada.Wide_Characters.Handling` (8652:2023 A.3.5) provides classification and conversion functions for `Wide_Character` values. All operations are pure functions. This package is retained without modification.

### 7a.4.6 A.3.6 -- The Package Wide_Wide_Characters.Handling

19. **Status: RETAINED.**

20. The package `Ada.Wide_Wide_Characters.Handling` (8652:2023 A.3.6) provides classification and conversion functions for `Wide_Wide_Character` values. All operations are pure functions. This package is retained without modification.

---

## 7a.5 A.4 -- String Handling

### 7a.5.1 A.4.1 -- The Package Strings

21. **Status: RETAINED.**

22. The package `Ada.Strings` (8652:2023 A.4.1) defines the types `Alignment`, `Truncation`, `Membership`, and `Direction`, as well as the exception `Length_Error`, `Pattern_Error`, `Index_Error`, and `Translation_Error`. The types are retained as they are simple enumeration types. The exception declarations exist in the emitted Ada for compatibility but are not raisable in Safe programs.

### 7a.5.2 A.4.2 -- The Package Strings.Maps

23. **Status: EXCLUDED.**

24. **Rationale:** The package `Ada.Strings.Maps` (8652:2023 A.4.2) defines the types `Character_Set` and `Character_Mapping` as private types. The implementation of these types in standard Ada libraries typically relies on controlled types or finalization for resource management. More critically, `Character_Mapping` is implemented as a tagged type or a type with user-defined assignment in many implementations, and the package's primary consumers are the generic string handling packages (A.4.3 through A.4.5), which are themselves excluded. Excluding this package has minimal impact since Safe programs use direct character operations from `Ada.Characters.Handling` instead.

### 7a.5.3 A.4.3 -- Fixed-Length String Handling (Ada.Strings.Fixed)

25. **Status: EXCLUDED.**

26. **Rationale:** The package `Ada.Strings.Fixed` (8652:2023 A.4.3) depends on `Ada.Strings.Maps` (excluded per paragraph 23) for its search and transformation operations. Many of its operations raise `Ada.Strings.Index_Error` or `Ada.Strings.Length_Error`. Safe programs use array slicing and `Ada.Characters.Handling` for string operations on fixed-length `String` values.

### 7a.5.4 A.4.4 -- Bounded-Length String Handling

27. **Status: EXCLUDED.**

28. **Rationale:** The package `Ada.Strings.Bounded` (8652:2023 A.4.4) is a generic package (`Generic_Bounded_Length`). Generics are excluded (D16).

### 7a.5.5 A.4.5 -- Unbounded-Length String Handling

29. **Status: EXCLUDED.**

30. **Rationale:** The package `Ada.Strings.Unbounded` (8652:2023 A.4.5) provides dynamically-allocated unbounded strings. It requires controlled types for automatic memory management (the `Unbounded_String` type is derived from `Ada.Finalization.Controlled` in standard implementations). Controlled types are excluded. Additionally, Safe's design philosophy uses fixed-length arrays and slices for string handling (D23), avoiding unbounded heap allocation.

### 7a.5.6 A.4.6 -- String-Handling Sets and Mappings

31. **Status: EXCLUDED.**

32. **Rationale:** The package `Ada.Strings.Maps.Constants` (8652:2023 A.4.6) depends on `Ada.Strings.Maps`, which is excluded (paragraph 23).

### 7a.5.7 A.4.7 -- Wide_String Handling

33. **Status: EXCLUDED.**

34. **Rationale:** The package `Ada.Strings.Wide_Fixed`, `Ada.Strings.Wide_Bounded`, and `Ada.Strings.Wide_Unbounded` (8652:2023 A.4.7) are the wide-character equivalents of A.4.3 through A.4.5. They are excluded for the same reasons: dependence on `Ada.Strings.Maps` variants, use of generics (bounded), and use of controlled types (unbounded).

### 7a.5.8 A.4.8 -- Wide_Wide_String Handling

35. **Status: EXCLUDED.**

36. **Rationale:** The packages for `Wide_Wide_String` handling (8652:2023 A.4.8) are excluded for the same reasons as A.4.7: dependence on maps, generics, and controlled types.

### 7a.5.9 A.4.9 -- String Hashing

37. **Status: EXCLUDED.**

38. **Rationale:** The packages `Ada.Strings.Hash`, `Ada.Strings.Fixed.Hash`, `Ada.Strings.Bounded.Hash`, and `Ada.Strings.Unbounded.Hash` (8652:2023 A.4.9) are defined as generic function instantiations or depend on excluded string packages. Generics are excluded (D16). A Safe program requiring string hashing shall implement the hash function directly.

### 7a.5.10 A.4.10 -- String Comparison

39. **Status: EXCLUDED.**

40. **Rationale:** The package `Ada.Strings.Less_Case_Insensitive` and related comparison functions (8652:2023 A.4.10) depend on `Ada.Strings.Maps` for their implementation. Excluded due to this dependency. Safe programs use direct character-by-character comparison with `Ada.Characters.Handling.To_Lower` or `To_Upper` for case-insensitive operations.

### 7a.5.11 A.4.11 -- String Encoding

41. **Status: EXCLUDED.**

42. **Rationale:** The package `Ada.Strings.UTF_Encoding` and its children (8652:2023 A.4.11) raise `Encoding_Error` as their primary error reporting mechanism. Several operations produce unbounded-length results. Excluded due to exception dependence and the complexity of the encoding interface. A Safe program requiring UTF encoding shall implement the encoding operations directly using array operations.

### 7a.5.12 A.4.12 -- Universal Text Buffers

43. **Status: EXCLUDED.**

44. **Rationale:** The package `Ada.Strings.Text_Buffers` (8652:2023 A.4.12) defines a tagged type (`Root_Buffer_Type`) as the root of the text buffer abstraction. Tagged types are excluded (D18).

---

## 7a.6 A.5 -- The Numerics Packages

### 7a.6.1 A.5.1 -- Elementary Functions

45. **Status: EXCLUDED.**

46. **Rationale:** The package `Ada.Numerics.Elementary_Functions` (8652:2023 A.5.1) is a generic package parameterized by a floating-point type. Generics are excluded (D16). The non-generic instance `Ada.Numerics.Float_Elementary_Functions` would also be excluded because it is defined as an instantiation of the generic.

47. **Note:** A future revision of Safe may provide non-generic elementary function packages for specific predefined floating-point types (e.g., `Safe.Float_Math`) if the need is established. For this specification, Safe programs requiring elementary functions (sin, cos, sqrt, etc.) shall implement them or access them through the emitted Ada layer.

### 7a.6.2 A.5.2 -- Random Number Generation

48. **Status: EXCLUDED.**

49. **Rationale:** The packages `Ada.Numerics.Float_Random` and `Ada.Numerics.Discrete_Random` (8652:2023 A.5.2) are excluded. `Discrete_Random` is a generic package (D16). `Float_Random` maintains internal mutable state (the generator state) and raises exceptions on misuse. Additionally, random number generation in safety-critical systems typically requires domain-specific, auditable generators rather than a general-purpose library.

### 7a.6.3 A.5.3 -- Attributes of Floating Point Types

50. **Status: RETAINED (as attributes, not as a package).**

51. The floating-point model attributes defined in 8652:2023 A.5.3 (`Machine_Radix`, `Machine_Mantissa`, `Machine_Emax`, `Machine_Emin`, `Denorm`, `Machine_Rounds`, `Machine_Overflows`, `Model_Mantissa`, `Model_Emin`, `Model_Epsilon`, `Model_Small`, `Safe_First`, `Safe_Last`) are retained as attributes on floating-point types. They are accessed via dot notation per Section 2.4.1. These are not a library package; they are type attributes defined by the language.

### 7a.6.4 A.5.4 -- Attributes of Fixed Point Types

52. **Status: RETAINED (as attributes, not as a package).**

53. The fixed-point type attributes defined in 8652:2023 A.5.4 (`Small`, `Delta`, `Fore`, `Round`, `Scale` for decimal types) are retained as attributes. See paragraph 51 for the same treatment.

### 7a.6.5 A.5.5 -- Big Numbers (Ada.Numerics.Big_Numbers)

54. **Status: EXCLUDED.**

55. **Rationale:** The package `Ada.Numerics.Big_Numbers` (8652:2023 A.5.5) is a namespace root for the big number packages. It is excluded because its children (A.5.6 and A.5.7) are excluded.

### 7a.6.6 A.5.6 -- Big Integers (Ada.Numerics.Big_Numbers.Big_Integers)

56. **Status: EXCLUDED.**

57. **Rationale:** The package `Ada.Numerics.Big_Numbers.Big_Integers` (8652:2023 A.5.6) defines `Big_Integer` as a private type with user-defined literals, controlled-type semantics for automatic storage management, and operator overloading. It requires tagged types (for the `Integer_Literal` aspect), controlled types, and user-defined operators, all of which are excluded.

### 7a.6.7 A.5.7 -- Big Reals (Ada.Numerics.Big_Numbers.Big_Reals)

58. **Status: EXCLUDED.**

59. **Rationale:** The package `Ada.Numerics.Big_Numbers.Big_Reals` (8652:2023 A.5.7) has the same dependencies as `Big_Integers` (paragraph 56): tagged types, controlled types, and user-defined operators. Excluded for the same reasons.

---

## 7a.7 A.6 -- Input-Output (Overview)

60. **Status: EXCLUDED.**

61. **Rationale:** 8652:2023 A.6 provides an overview of the input-output model. The Ada I/O library is deeply intertwined with exceptions (every I/O operation can raise `Status_Error`, `Mode_Error`, `Name_Error`, `Use_Error`, `Device_Error`, or `End_Error`), controlled types (file objects require finalization), and in some cases generics. The entire Ada I/O subsystem (A.6 through A.14) is excluded from the Safe predefined library.

62. Safe programs that require I/O shall use the emitted Ada's access to the Ada I/O libraries outside the Safe language scope, or shall use implementation-defined I/O packages documented by the Safe implementation. A future revision of this specification may define a Safe-specific I/O model with explicit error returns instead of exceptions.

---

## 7a.8 A.7 -- External Files and File Objects

63. **Status: EXCLUDED.**

64. **Rationale:** The package `Ada.IO_Exceptions` and the file model defined in 8652:2023 A.7 depend on exceptions and controlled types. See paragraph 61.

---

## 7a.9 A.8 -- Sequential and Direct Files

### 7a.9.1 A.8.1 -- The Generic Package Sequential_IO

65. **Status: EXCLUDED.**

66. **Rationale:** `Ada.Sequential_IO` (8652:2023 A.8.1) is a generic package (D16). It also raises exceptions on every operation and requires controlled file types for finalization.

### 7a.9.2 A.8.4 -- The Generic Package Direct_IO

67. **Status: EXCLUDED.**

68. **Rationale:** `Ada.Direct_IO` (8652:2023 A.8.4) is a generic package (D16). Same exclusion reasons as `Sequential_IO` (paragraph 65).

---

## 7a.10 A.9 -- The Generic Package Storage_IO

69. **Status: EXCLUDED.**

70. **Rationale:** `Ada.Storage_IO` (8652:2023 A.9) is a generic package (D16).

---

## 7a.11 A.10 -- Text Input-Output

### 7a.11.1 A.10.1 -- The Package Text_IO

71. **Status: EXCLUDED.**

72. **Rationale:** `Ada.Text_IO` (8652:2023 A.10.1) is excluded. It requires controlled file types, raises exceptions on every operation (`Status_Error`, `Mode_Error`, `Name_Error`, `Use_Error`, `Device_Error`, `End_Error`, `Data_Error`, `Layout_Error`), and contains internal generic packages (`Integer_IO`, `Float_IO`, `Enumeration_IO`, etc.). The package combines generics, exceptions, and controlled types -- all three excluded feature categories.

### 7a.11.2 A.10.2 through A.10.10 -- Text_IO Operations

73. **Status: EXCLUDED.**

74. **Rationale:** These subsections (8652:2023 A.10.2 through A.10.10) define the operations of `Ada.Text_IO`. They are excluded as part of the `Text_IO` exclusion (paragraph 71).

### 7a.11.3 A.10.11 -- Input-Output for Bounded Strings

75. **Status: EXCLUDED.**

76. **Rationale:** Depends on `Ada.Text_IO` (excluded) and `Ada.Strings.Bounded` (excluded, generic).

### 7a.11.4 A.10.12 -- Input-Output for Unbounded Strings

77. **Status: EXCLUDED.**

78. **Rationale:** Depends on `Ada.Text_IO` (excluded) and `Ada.Strings.Unbounded` (excluded, controlled types).

---

## 7a.12 A.11 -- Wide Text Input-Output and Wide Wide Text Input-Output

79. **Status: EXCLUDED.**

80. **Rationale:** `Ada.Wide_Text_IO` and `Ada.Wide_Wide_Text_IO` (8652:2023 A.11) are the wide-character equivalents of `Ada.Text_IO`. Excluded for the same reasons (paragraph 71): controlled file types, exceptions, and internal generic packages.

---

## 7a.13 A.12 -- Stream Input-Output

### 7a.13.1 A.12.1 -- The Package Streams.Stream_IO

81. **Status: EXCLUDED.**

82. **Rationale:** `Ada.Streams.Stream_IO` (8652:2023 A.12.1) depends on stream types (excluded per Section 2, 13.13), controlled file types, and exceptions.

### 7a.13.2 A.12.2 -- The Package Text_IO.Text_Streams

83. **Status: EXCLUDED.**

84. **Rationale:** Depends on both `Ada.Text_IO` (excluded) and `Ada.Streams` (excluded).

### 7a.13.3 A.12.3 -- The Package Wide_Text_IO.Text_Streams

85. **Status: EXCLUDED.**

86. **Rationale:** Depends on `Ada.Wide_Text_IO` (excluded) and `Ada.Streams` (excluded).

### 7a.13.4 A.12.4 -- The Package Wide_Wide_Text_IO.Text_Streams

87. **Status: EXCLUDED.**

88. **Rationale:** Depends on `Ada.Wide_Wide_Text_IO` (excluded) and `Ada.Streams` (excluded).

---

## 7a.14 A.13 -- Exceptions in Input-Output

89. **Status: EXCLUDED.**

90. **Rationale:** The package `Ada.IO_Exceptions` (8652:2023 A.13) defines the I/O exception types (`Status_Error`, `Mode_Error`, `Name_Error`, `Use_Error`, `Device_Error`, `Data_Error`, `Layout_Error`, `End_Error`). Exceptions are excluded (D14) and the I/O subsystem is excluded (paragraph 61).

---

## 7a.15 A.14 -- File Sharing

91. **Status: EXCLUDED.**

92. **Rationale:** 8652:2023 A.14 defines the rules for sharing files between I/O packages. The I/O subsystem is excluded (paragraph 61).

---

## 7a.16 A.15 -- The Package Command_Line

93. **Status: EXCLUDED.**

94. **Rationale:** The package `Ada.Command_Line` (8652:2023 A.15) provides access to command-line arguments and the program exit status. Its operations raise `Constraint_Error` when argument indices are out of range, and `Set_Exit_Status` interacts with the runtime environment in implementation-defined ways. Exceptions are excluded (D14).

95. **Note:** A Safe implementation may provide an implementation-defined package for command-line access with explicit error returns instead of exceptions. Such a package is outside the scope of this specification.

### 7a.16.1 A.15.1 -- The Packages Wide_Command_Line and Wide_Wide_Command_Line

96. **Status: EXCLUDED.**

97. **Rationale:** Excluded for the same reasons as `Ada.Command_Line` (paragraph 93).

---

## 7a.17 A.16 -- The Package Directories

98. **Status: EXCLUDED.**

99. **Rationale:** The package `Ada.Directories` (8652:2023 A.16) provides file system operations (directory listing, file existence, file size, etc.). Every operation raises exceptions (`Name_Error`, `Use_Error`, `Status_Error`), and directory search operations use controlled types (`Search_Type`, `Directory_Entry_Type`). Excluded due to dependence on exceptions and controlled types.

### 7a.17.1 A.16.1 -- The Package Directories.Hierarchical_File_Names

100. **Status: EXCLUDED.**

101. **Rationale:** Depends on `Ada.Directories` (excluded, paragraph 98).

### 7a.17.2 A.16.2 -- The Packages Wide_Directories and Wide_Wide_Directories

102. **Status: EXCLUDED.**

103. **Rationale:** Excluded for the same reasons as `Ada.Directories` (paragraph 98).

---

## 7a.18 A.17 -- The Package Environment_Variables

104. **Status: EXCLUDED.**

105. **Rationale:** The package `Ada.Environment_Variables` (8652:2023 A.17) provides access to operating system environment variables. Its `Value` function raises `Constraint_Error` when a variable does not exist, and `Iterate` uses an access-to-subprogram parameter (excluded per Section 2, D17). Excluded due to dependence on exceptions and access-to-subprogram types.

### 7a.18.1 A.17.1 -- The Packages Wide_Environment_Variables and Wide_Wide_Environment_Variables

106. **Status: EXCLUDED.**

107. **Rationale:** Excluded for the same reasons as `Ada.Environment_Variables` (paragraph 104).

---

## 7a.19 A.18 -- Containers

### 7a.19.1 A.18.1 -- The Package Containers

108. **Status: EXCLUDED.**

109. **Rationale:** The package `Ada.Containers` (8652:2023 A.18.1) defines the root types and exceptions for the container library (`Hash_Type`, `Count_Type`, `Capacity_Error`). While it is a simple declarations-only package, its sole purpose is to support the container packages (A.18.2 through A.18.32), all of which are excluded. Retaining this package in isolation serves no purpose.

### 7a.19.2 A.18.2 -- The Generic Package Containers.Vectors

110. **Status: EXCLUDED.**

111. **Rationale:** `Ada.Containers.Vectors` (8652:2023 A.18.2) is a generic package (D16). It also requires tagged types (vector cursors), controlled types (automatic storage management), and raises exceptions.

### 7a.19.3 A.18.3 -- The Generic Package Containers.Doubly_Linked_Lists

112. **Status: EXCLUDED.**

113. **Rationale:** `Ada.Containers.Doubly_Linked_Lists` (8652:2023 A.18.3) is a generic package (D16). Same additional exclusion reasons as Vectors (paragraph 111).

### 7a.19.4 A.18.4 -- Maps (Overview)

114. **Status: EXCLUDED.**

115. **Rationale:** 8652:2023 A.18.4 provides the overview for map containers. All map packages are generic and excluded (D16).

### 7a.19.5 A.18.5 -- The Generic Package Containers.Hashed_Maps

116. **Status: EXCLUDED.**

117. **Rationale:** Generic package (D16). Also requires tagged types and controlled types.

### 7a.19.6 A.18.6 -- The Generic Package Containers.Ordered_Maps

118. **Status: EXCLUDED.**

119. **Rationale:** Generic package (D16). Also requires tagged types and controlled types.

### 7a.19.7 A.18.7 -- Sets (Overview)

120. **Status: EXCLUDED.**

121. **Rationale:** 8652:2023 A.18.7 provides the overview for set containers. All set packages are generic and excluded (D16).

### 7a.19.8 A.18.8 -- The Generic Package Containers.Hashed_Sets

122. **Status: EXCLUDED.**

123. **Rationale:** Generic package (D16). Also requires tagged types and controlled types.

### 7a.19.9 A.18.9 -- The Generic Package Containers.Ordered_Sets

124. **Status: EXCLUDED.**

125. **Rationale:** Generic package (D16). Also requires tagged types and controlled types.

### 7a.19.10 A.18.10 -- The Generic Package Containers.Multiway_Trees

126. **Status: EXCLUDED.**

127. **Rationale:** Generic package (D16). Also requires tagged types and controlled types.

### 7a.19.11 A.18.11 -- The Generic Package Containers.Indefinite_Vectors

128. **Status: EXCLUDED.**

129. **Rationale:** Generic package (D16). Also requires indefinite types, tagged types, and controlled types.

### 7a.19.12 A.18.12 -- The Generic Package Containers.Indefinite_Doubly_Linked_Lists

130. **Status: EXCLUDED.**

131. **Rationale:** Generic package (D16).

### 7a.19.13 A.18.13 -- The Generic Package Containers.Indefinite_Hashed_Maps

132. **Status: EXCLUDED.**

133. **Rationale:** Generic package (D16).

### 7a.19.14 A.18.14 -- The Generic Package Containers.Indefinite_Ordered_Maps

134. **Status: EXCLUDED.**

135. **Rationale:** Generic package (D16).

### 7a.19.15 A.18.15 -- The Generic Package Containers.Indefinite_Hashed_Sets

136. **Status: EXCLUDED.**

137. **Rationale:** Generic package (D16).

### 7a.19.16 A.18.16 -- The Generic Package Containers.Indefinite_Ordered_Sets

138. **Status: EXCLUDED.**

139. **Rationale:** Generic package (D16).

### 7a.19.17 A.18.17 -- The Generic Package Containers.Indefinite_Multiway_Trees

140. **Status: EXCLUDED.**

141. **Rationale:** Generic package (D16).

### 7a.19.18 A.18.18 -- The Generic Package Containers.Indefinite_Holders

142. **Status: EXCLUDED.**

143. **Rationale:** Generic package (D16). Also requires controlled types for automatic storage management of indefinite values.

### 7a.19.19 A.18.19 -- The Generic Package Containers.Bounded_Vectors

144. **Status: EXCLUDED.**

145. **Rationale:** Generic package (D16).

### 7a.19.20 A.18.20 -- The Generic Package Containers.Bounded_Doubly_Linked_Lists

146. **Status: EXCLUDED.**

147. **Rationale:** Generic package (D16).

### 7a.19.21 A.18.21 -- The Generic Package Containers.Bounded_Hashed_Maps

148. **Status: EXCLUDED.**

149. **Rationale:** Generic package (D16).

### 7a.19.22 A.18.22 -- The Generic Package Containers.Bounded_Ordered_Maps

150. **Status: EXCLUDED.**

151. **Rationale:** Generic package (D16).

### 7a.19.23 A.18.23 -- The Generic Package Containers.Bounded_Hashed_Sets

152. **Status: EXCLUDED.**

153. **Rationale:** Generic package (D16).

### 7a.19.24 A.18.24 -- The Generic Package Containers.Bounded_Ordered_Sets

154. **Status: EXCLUDED.**

155. **Rationale:** Generic package (D16).

### 7a.19.25 A.18.25 -- The Generic Package Containers.Bounded_Multiway_Trees

156. **Status: EXCLUDED.**

157. **Rationale:** Generic package (D16).

### 7a.19.26 A.18.26 -- Array Sorting

158. **Status: EXCLUDED.**

159. **Rationale:** The generic procedures `Ada.Containers.Generic_Sort`, `Ada.Containers.Generic_Constrained_Array_Sort`, and `Ada.Containers.Generic_Array_Sort` (8652:2023 A.18.26) are generic subprograms (D16). A Safe program requiring array sorting shall implement the sort algorithm directly.

### 7a.19.27 A.18.27 -- The Generic Package Containers.Synchronized_Queue_Interfaces

160. **Status: EXCLUDED.**

161. **Rationale:** Generic package (D16). Also defines a synchronized interface type (tagged, D18). Safe provides typed channels (D28) as the concurrency-safe queue mechanism.

### 7a.19.28 A.18.28 -- The Generic Package Containers.Unbounded_Synchronized_Queues

162. **Status: EXCLUDED.**

163. **Rationale:** Generic package (D16). Also requires tagged types and protected types. Safe provides typed channels (D28) instead.

### 7a.19.29 A.18.29 -- The Generic Package Containers.Bounded_Synchronized_Queues

164. **Status: EXCLUDED.**

165. **Rationale:** Generic package (D16). Also requires tagged types and protected types. Safe provides typed channels (D28) instead.

### 7a.19.30 A.18.30 -- The Generic Package Containers.Unbounded_Priority_Queues

166. **Status: EXCLUDED.**

167. **Rationale:** Generic package (D16). Also requires tagged types and protected types.

### 7a.19.31 A.18.31 -- The Generic Package Containers.Bounded_Priority_Queues

168. **Status: EXCLUDED.**

169. **Rationale:** Generic package (D16). Also requires tagged types and protected types.

### 7a.19.32 A.18.32 -- The Generic Package Containers.Bounded_Indefinite_Holders

170. **Status: EXCLUDED.**

171. **Rationale:** Generic package (D16).

### 7a.19.33 A.18.33 -- Example of Container Use

172. This subsection (8652:2023 A.18.33) provides examples only and defines no library units. It is not applicable.

---

## 7a.20 A.19 -- The Package Locales

173. **Status: EXCLUDED.**

174. **Rationale:** The package `Ada.Locales` (8652:2023 A.19) provides locale information (country and language codes). It depends on the implementation's interaction with the operating system environment and raises exceptions on error. Excluded due to exception dependence and limited utility for systems programming.

---

## 7a.21 Predefined Packages Outside Annex A

The following predefined packages are defined outside Annex A but are relevant to Safe programs.

### 7a.21.1 System (13.7)

175. **Status: RETAINED.**

176. The package `System` (8652:2023 13.7) defines the implementation-defined constants and types for the target machine: `Name`, `Min_Int`, `Max_Int`, `Max_Binary_Modulus`, `Max_Nonbinary_Modulus`, `Max_Base_Digits`, `Max_Digits`, `Fine_Delta`, `Tick`, `Storage_Unit`, `Word_Size`, `Memory_Size`, `Address`, `Null_Address`, `Default_Bit_Order`, `Any_Priority`, `Priority`, `Interrupt_Priority`, and the subtype `Default_Priority`. These are essential for systems programming and representation clauses.

### 7a.21.2 System.Storage_Elements (13.7.1)

177. **Status: RETAINED.**

178. The package `System.Storage_Elements` (8652:2023 13.7.1) defines `Storage_Offset`, `Storage_Count`, `Storage_Element`, `Storage_Array`, and address arithmetic operations. These types are required for representation clauses and low-level memory layout. The package is retained without modification.

### 7a.21.3 System.Address_To_Access_Conversions (13.7.2)

179. **Status: EXCLUDED.**

180. **Rationale:** The generic package `System.Address_To_Access_Conversions` (8652:2023 13.7.2) provides unchecked conversion between addresses and access values. It is a generic package (D16) and performs unsafe conversions that bypass the ownership model (D24). Excluded on both grounds.

### 7a.21.4 Ada.Unchecked_Conversion (13.9)

181. **Status: EXCLUDED.**

182. **Rationale:** The generic function `Ada.Unchecked_Conversion` (8652:2023 13.9) is a generic unit (D16) and performs unchecked type conversions that bypass the type system (D24). Excluded on both grounds.

### 7a.21.5 Ada.Unchecked_Deallocation (13.11.2)

183. **Status: EXCLUDED.**

184. **Rationale:** The generic procedure `Ada.Unchecked_Deallocation` (8652:2023 13.11.2) is a generic unit (D16). Additionally, explicit deallocation is excluded from Safe programs; deallocation occurs automatically when the owning access variable goes out of scope (D17, Section 2.3). The compiler generates deallocation calls in the emitted Ada.

### 7a.21.6 Ada.Finalization (7.6)

185. **Status: EXCLUDED.**

186. **Rationale:** The package `Ada.Finalization` (8652:2023 7.6) defines the tagged types `Controlled` and `Limited_Controlled`, which are the roots of the finalization framework. Tagged types are excluded (D18) and controlled types are excluded (Section 2, 7.6). Safe uses automatic deallocation via the ownership model instead of user-defined finalization.

### 7a.21.7 Ada.Exceptions (11.4.1)

187. **Status: EXCLUDED.**

188. **Rationale:** The package `Ada.Exceptions` (8652:2023 11.4.1) provides exception identification and information. Exceptions are excluded in their entirety (D14).

### 7a.21.8 Ada.Real_Time (D.8)

189. **Status: RETAINED.**

190. The package `Ada.Real_Time` (8652:2023 D.8) defines the type `Time` and the type `Time_Span` for monotonic clock access. It provides the function `Clock`, arithmetic on `Time` and `Time_Span` values, the constant `Time_Unit`, and conversion functions `To_Duration`, `To_Time_Span`, `Nanoseconds`, `Microseconds`, `Milliseconds`, and `Seconds`.

191. This package is retained because `delay until` statements in Safe task bodies require a monotonic time source. The `Ada.Real_Time.Clock` function and `Time_Span` arithmetic are the standard mechanism for computing absolute deadlines for periodic tasks.

192. **Note:** The child package `Ada.Real_Time.Timing_Events` (8652:2023 D.15) is excluded. Timing events require protected procedure handlers and are part of the full real-time annex, which is excluded (Section 2, Annex D).

### 7a.21.9 Ada.Task_Identification (C.7.1)

193. **Status: EXCLUDED.**

194. **Rationale:** The package `Ada.Task_Identification` (8652:2023 C.7.1) provides task identity querying. Full Ada tasking features are excluded (D15). Safe's task model provides no runtime task identity mechanism.

### 7a.21.10 Ada.Synchronous_Task_Control (D.10)

195. **Status: EXCLUDED.**

196. **Rationale:** The package `Ada.Synchronous_Task_Control` (8652:2023 D.10) provides suspension objects for inter-task synchronization. Safe uses typed channels (D28) for all inter-task communication and synchronization. Suspension objects are superseded by channel operations.

### 7a.21.11 Ada.Synchronous_Barriers (D.10.1)

197. **Status: EXCLUDED.**

198. **Rationale:** The package `Ada.Synchronous_Barriers` (8652:2023 D.10.1) provides barrier synchronization for tasks. Excluded for the same reason as other tasking packages (D15). Safe's concurrency model uses channels, not barriers.

### 7a.21.12 Ada.Asynchronous_Task_Control (D.11)

199. **Status: EXCLUDED.**

200. **Rationale:** The package `Ada.Asynchronous_Task_Control` (8652:2023 D.11) provides operations to hold and continue tasks. Excluded as part of the full tasking exclusion (D15).

### 7a.21.13 Ada.Execution_Time (D.14)

201. **Status: EXCLUDED.**

202. **Rationale:** The package `Ada.Execution_Time` and its children (8652:2023 D.14 through D.14.3) provide CPU time measurement and execution time timers. These are part of the real-time annex features excluded in Section 2 (Annex D).

### 7a.21.14 System.Atomic_Operations (C.6.1 through C.6.5)

203. **Status: EXCLUDED.**

204. **Rationale:** The packages under `System.Atomic_Operations` (8652:2023 C.6.1 through C.6.5) provide atomic operations (`Exchange`, `Test_and_Set`, `Integer_Arithmetic`, `Modular_Arithmetic`). These are system-level primitives excluded as part of the shared variable control exclusion (Section 2, Annex C). Safe's concurrency model uses channels rather than shared memory with atomic operations.

### 7a.21.15 Ada.Numerics (A.5)

205. **Status: RETAINED.**

206. The package `Ada.Numerics` (8652:2023 A.5) defines the constants `Pi` and `e` as named numbers. It is a pure declarations-only package and is retained without modification.

### 7a.21.16 Ada.Streams (13.13.1)

207. **Status: EXCLUDED.**

208. **Rationale:** The package `Ada.Streams` (8652:2023 13.13.1) defines the root tagged type `Root_Stream_Type` for the stream subsystem. Tagged types are excluded (D18) and streams are excluded (Section 2, 13.13).

---

## 7a.22 Annex B -- Interface to Other Languages

209. **Status: EXCLUDED IN ITS ENTIRETY.**

210. The entirety of 8652:2023 Annex B (Interface to Other Languages), comprising sections B.1 through B.5, is excluded. This includes:

- B.1 Interfacing Aspects (`Convention`, `Import`, `Export`, `External_Name`, `Link_Name`)
- B.2 The Package Interfaces (`Interfaces`, `Interfaces.C`, `Interfaces.C.Strings`, `Interfaces.C.Pointers`, `Interfaces.COBOL`, `Interfaces.Fortran`)
- B.3 Interfacing with C and C++ (including `Interfaces.C.Strings`, `Interfaces.C.Pointers`, and unchecked unions)
- B.4 Interfacing with COBOL
- B.5 Interfacing with Fortran

211. **Rationale:** An imported foreign-language function is an unverifiable hole in the Silver guarantee (D24). GNATprove cannot analyze C, C++, COBOL, or Fortran code, so any call to a foreign function breaks the Absence-of-Runtime-Errors proof chain. Foreign function interface is reserved for a future system sublanguage specification. This specification defines only the safe language floor.

---

## 7a.23 Summary Table

212. The following table summarizes the classification of all Annex A library units and relevant predefined packages.

| 8652:2023 Reference | Package / Unit | Status | Exclusion Reason |
|---------------------|----------------|--------|------------------|
| A.1 | `Standard` | RETAINED | -- |
| A.2 | `Ada` | RETAINED | -- |
| A.3.1 | `Ada.Characters` / `Ada.Wide_Characters` / `Ada.Wide_Wide_Characters` | RETAINED | -- |
| A.3.2 | `Ada.Characters.Handling` | RETAINED | -- |
| A.3.3 | `Ada.Characters.Latin_1` | RETAINED | -- |
| A.3.4 | `Ada.Characters.Conversions` | RETAINED | -- |
| A.3.5 | `Ada.Wide_Characters.Handling` | RETAINED | -- |
| A.3.6 | `Ada.Wide_Wide_Characters.Handling` | RETAINED | -- |
| A.4.1 | `Ada.Strings` | RETAINED | -- |
| A.4.2 | `Ada.Strings.Maps` | EXCLUDED | Controlled/tagged types; consumers excluded |
| A.4.3 | `Ada.Strings.Fixed` | EXCLUDED | Depends on excluded Maps; exceptions |
| A.4.4 | `Ada.Strings.Bounded` | EXCLUDED | Generic (D16) |
| A.4.5 | `Ada.Strings.Unbounded` | EXCLUDED | Controlled types; heap allocation |
| A.4.6 | `Ada.Strings.Maps.Constants` | EXCLUDED | Depends on excluded Maps |
| A.4.7 | Wide_String handling packages | EXCLUDED | Same as A.4.3--A.4.5 |
| A.4.8 | Wide_Wide_String handling packages | EXCLUDED | Same as A.4.3--A.4.5 |
| A.4.9 | String hashing packages | EXCLUDED | Generic (D16) |
| A.4.10 | String comparison packages | EXCLUDED | Depends on excluded Maps |
| A.4.11 | `Ada.Strings.UTF_Encoding` and children | EXCLUDED | Exceptions; complex interface |
| A.4.12 | `Ada.Strings.Text_Buffers` | EXCLUDED | Tagged types (D18) |
| A.5 | `Ada.Numerics` | RETAINED | -- |
| A.5.1 | `Ada.Numerics.Elementary_Functions` | EXCLUDED | Generic (D16) |
| A.5.2 | `Ada.Numerics.Float_Random` / `Discrete_Random` | EXCLUDED | Generic (D16); mutable state; exceptions |
| A.5.3 | Floating-point model attributes | RETAINED | (as type attributes, not a package) |
| A.5.4 | Fixed-point type attributes | RETAINED | (as type attributes, not a package) |
| A.5.5 | `Ada.Numerics.Big_Numbers` | EXCLUDED | Children excluded |
| A.5.6 | `Ada.Numerics.Big_Numbers.Big_Integers` | EXCLUDED | Tagged types; controlled types; operators |
| A.5.7 | `Ada.Numerics.Big_Numbers.Big_Reals` | EXCLUDED | Tagged types; controlled types; operators |
| A.6 | Input-Output (overview) | EXCLUDED | Exceptions; controlled types |
| A.7 | External Files and File Objects | EXCLUDED | Exceptions; controlled types |
| A.8.1 | `Ada.Sequential_IO` | EXCLUDED | Generic (D16); exceptions |
| A.8.4 | `Ada.Direct_IO` | EXCLUDED | Generic (D16); exceptions |
| A.9 | `Ada.Storage_IO` | EXCLUDED | Generic (D16) |
| A.10.1 | `Ada.Text_IO` | EXCLUDED | Generics; exceptions; controlled types |
| A.10.2--A.10.10 | Text_IO operations | EXCLUDED | Part of Text_IO |
| A.10.11 | Bounded string I/O | EXCLUDED | Depends on excluded packages |
| A.10.12 | Unbounded string I/O | EXCLUDED | Depends on excluded packages |
| A.11 | `Ada.Wide_Text_IO` / `Ada.Wide_Wide_Text_IO` | EXCLUDED | Same as Text_IO |
| A.12.1 | `Ada.Streams.Stream_IO` | EXCLUDED | Streams; controlled types; exceptions |
| A.12.2 | `Ada.Text_IO.Text_Streams` | EXCLUDED | Streams; depends on Text_IO |
| A.12.3 | `Ada.Wide_Text_IO.Text_Streams` | EXCLUDED | Streams; depends on Wide_Text_IO |
| A.12.4 | `Ada.Wide_Wide_Text_IO.Text_Streams` | EXCLUDED | Streams; depends on Wide_Wide_Text_IO |
| A.13 | `Ada.IO_Exceptions` | EXCLUDED | Exceptions (D14) |
| A.14 | File Sharing | EXCLUDED | I/O subsystem excluded |
| A.15 | `Ada.Command_Line` | EXCLUDED | Exceptions |
| A.15.1 | Wide/Wide_Wide_Command_Line | EXCLUDED | Exceptions |
| A.16 | `Ada.Directories` | EXCLUDED | Exceptions; controlled types |
| A.16.1 | `Ada.Directories.Hierarchical_File_Names` | EXCLUDED | Depends on excluded Directories |
| A.16.2 | Wide/Wide_Wide_Directories | EXCLUDED | Depends on excluded Directories |
| A.17 | `Ada.Environment_Variables` | EXCLUDED | Exceptions; access-to-subprogram |
| A.17.1 | Wide/Wide_Wide_Environment_Variables | EXCLUDED | Same as Environment_Variables |
| A.18.1 | `Ada.Containers` | EXCLUDED | All consumers excluded |
| A.18.2--A.18.32 | All container packages | EXCLUDED | Generic (D16) |
| A.19 | `Ada.Locales` | EXCLUDED | Exceptions; limited utility |
| 13.7 | `System` | RETAINED | -- |
| 13.7.1 | `System.Storage_Elements` | RETAINED | -- |
| 13.7.2 | `System.Address_To_Access_Conversions` | EXCLUDED | Generic (D16); unsafe (D24) |
| 13.9 | `Ada.Unchecked_Conversion` | EXCLUDED | Generic (D16); unsafe (D24) |
| 13.11.2 | `Ada.Unchecked_Deallocation` | EXCLUDED | Generic (D16); ownership model |
| 13.13.1 | `Ada.Streams` | EXCLUDED | Tagged types (D18); streams excluded |
| 7.6 | `Ada.Finalization` | EXCLUDED | Tagged types (D18); controlled types excluded |
| 11.4.1 | `Ada.Exceptions` | EXCLUDED | Exceptions (D14) |
| D.8 | `Ada.Real_Time` | RETAINED | Required for `delay until` |
| C.7.1 | `Ada.Task_Identification` | EXCLUDED | Full tasking excluded (D15) |
| D.10 | `Ada.Synchronous_Task_Control` | EXCLUDED | Full tasking excluded (D15) |
| D.10.1 | `Ada.Synchronous_Barriers` | EXCLUDED | Full tasking excluded (D15) |
| D.11 | `Ada.Asynchronous_Task_Control` | EXCLUDED | Full tasking excluded (D15) |
| D.14 | `Ada.Execution_Time` and children | EXCLUDED | Real-time annex excluded |
| C.6.1--C.6.5 | `System.Atomic_Operations` and children | EXCLUDED | System sublanguage (D24) |
| B.1--B.5 | All Annex B packages | EXCLUDED | Foreign interface (D24) |

---

## 7a.24 Retained Library -- Complete List

213. For convenience, the following is the complete list of library units that a conforming Safe implementation shall provide:

1. `Standard` (A.1)
2. `Ada` (A.2)
3. `Ada.Characters` (A.3.1)
4. `Ada.Wide_Characters` (A.3.1)
5. `Ada.Wide_Wide_Characters` (A.3.1)
6. `Ada.Characters.Handling` (A.3.2)
7. `Ada.Characters.Latin_1` (A.3.3)
8. `Ada.Characters.Conversions` (A.3.4)
9. `Ada.Wide_Characters.Handling` (A.3.5)
10. `Ada.Wide_Wide_Characters.Handling` (A.3.6)
11. `Ada.Strings` (A.4.1)
12. `Ada.Numerics` (A.5)
13. `System` (13.7)
14. `System.Storage_Elements` (13.7.1)
15. `Ada.Real_Time` (D.8)

214. All other predefined library units of 8652:2023 are excluded from Safe programs. A conforming implementation shall not make excluded library units available through Safe's `with` clause mechanism.

215. **Implementation permission:** A conforming implementation may provide additional implementation-defined library units outside the `Ada` and `System` hierarchies for capabilities not covered by the retained library (e.g., I/O with explicit error returns, command-line access, file system operations). Such packages shall be documented and shall not use any feature excluded from Safe.
