with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Builtin_Types;

package body Safe_Frontend.Ada_Emit is
   package SU renames Ada.Strings.Unbounded;
   package BT renames Safe_Frontend.Builtin_Types;

   use type Ada.Containers.Count_Type;
   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type CM.Statement_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Select_Arm_Kind;
   use type FT.UString;
   use type GM.Scalar_Value_Kind;

   Indent_Width : constant Positive := 3;

   Emitter_Unsupported : exception;
   Emitter_Internal    : exception;

   Runtime_Template : constant String :=
     "--  Safe Language Runtime Type Definitions" & ASCII.LF
     & "--" & ASCII.LF
     & "--  Clause: SAFE@468cf72:spec/02-restrictions.md#2.8.1.p126:812b54a8" & ASCII.LF
     & "--  Reference: compiler/translation_rules.md Section 8.1" & ASCII.LF
     & "--" & ASCII.LF
     & "--  Every integer arithmetic expression in the Safe language is evaluated" & ASCII.LF
     & "--  in a mathematical integer type. The compiler emits all intermediate" & ASCII.LF
     & "--  computations using Wide_Integer, which provides at least 64-bit signed" & ASCII.LF
     & "--  range. Range checks occur only at narrowing points: assignment," & ASCII.LF
     & "--  parameter passing, return, type conversion, and type annotation." & ASCII.LF
     & ASCII.LF
     & "pragma SPARK_Mode (On);" & ASCII.LF
     & ASCII.LF
     & "package Safe_Runtime" & ASCII.LF
     & "  with Pure" & ASCII.LF
     & "is" & ASCII.LF
     & ASCII.LF
     & "   type Wide_Integer is range -(2 ** 63) .. (2 ** 63 - 1);" & ASCII.LF
     & "   --  Wide intermediate type for all integer arithmetic in emitted code." & ASCII.LF
     & "   --  Corresponds to the mathematical integer semantics of the Safe language." & ASCII.LF
     & "   --  The compiler lifts all integer operands to Wide_Integer before" & ASCII.LF
     & "   --  performing arithmetic, then narrows at the five defined narrowing" & ASCII.LF
     & "   --  points (assignment, parameter, return, conversion, annotation)." & ASCII.LF
     & ASCII.LF
     & "end Safe_Runtime;" & ASCII.LF;

   String_RT_Spec_Template : constant String :=
     "pragma SPARK_Mode (On);" & ASCII.LF
     & ASCII.LF
     & "package Safe_String_RT is" & ASCII.LF
     & "   type Safe_String is private;" & ASCII.LF
     & ASCII.LF
     & "   Empty : constant Safe_String;" & ASCII.LF
     & ASCII.LF
     & "   function From_Literal (Value : String) return Safe_String" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (From_Literal'Result => Value);" & ASCII.LF
     & "   function Clone (Source : Safe_String) return Safe_String" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Clone'Result => Source);" & ASCII.LF
     & "   procedure Copy (Target : in out Safe_String; Source : Safe_String)" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Target => (Target, Source));" & ASCII.LF
     & "   procedure Free (Value : in out Safe_String)" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Value => Value);" & ASCII.LF
     & ASCII.LF
     & "   function To_String (Value : Safe_String) return String" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (To_String'Result => Value);" & ASCII.LF
     & "   function Length (Value : Safe_String) return Natural" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Length'Result => Value);" & ASCII.LF
     & "   function Slice (Value : Safe_String; Low, High : Natural) return Safe_String" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Slice'Result => (Value, Low, High));" & ASCII.LF
     & "   function Concat (Left, Right : Safe_String) return Safe_String" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Concat'Result => (Left, Right));" & ASCII.LF
     & "   function Equal (Left, Right : Safe_String) return Boolean" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Equal'Result => (Left, Right));" & ASCII.LF
     & ASCII.LF
     & "private" & ASCII.LF
     & "   pragma SPARK_Mode (Off);" & ASCII.LF
     & "   type String_Access is access String;" & ASCII.LF
     & "   type Safe_String is record" & ASCII.LF
     & "      Data : String_Access := null;" & ASCII.LF
     & "   end record;" & ASCII.LF
     & "   Empty : constant Safe_String := (Data => null);" & ASCII.LF
     & "end Safe_String_RT;" & ASCII.LF;

   String_RT_Body_Template : constant String :=
     "with Ada.Unchecked_Deallocation;" & ASCII.LF
     & ASCII.LF
     & "package body Safe_String_RT is" & ASCII.LF
     & "   pragma SPARK_Mode (Off);" & ASCII.LF
     & "   procedure Free_String is new Ada.Unchecked_Deallocation (String, String_Access);" & ASCII.LF
     & ASCII.LF
     & "   function From_Literal (Value : String) return Safe_String is" & ASCII.LF
     & "      Result : Safe_String := Empty;" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value'Length > 0 then" & ASCII.LF
     & "         Result.Data := new String'(Value);" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return Result;" & ASCII.LF
     & "   end From_Literal;" & ASCII.LF
     & ASCII.LF
     & "   function Clone (Source : Safe_String) return Safe_String is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Source.Data = null then" & ASCII.LF
     & "         return Empty;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return (Data => new String'(Source.Data.all));" & ASCII.LF
     & "   end Clone;" & ASCII.LF
     & ASCII.LF
     & "   procedure Copy (Target : in out Safe_String; Source : Safe_String) is" & ASCII.LF
     & "      Snapshot : constant Safe_String := Clone (Source);" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      Free (Target);" & ASCII.LF
     & "      Target := Snapshot;" & ASCII.LF
     & "   end Copy;" & ASCII.LF
     & ASCII.LF
     & "   procedure Free (Value : in out Safe_String) is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value.Data /= null then" & ASCII.LF
     & "         Free_String (Value.Data);" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      Value := Empty;" & ASCII.LF
     & "   end Free;" & ASCII.LF
     & ASCII.LF
     & "   function To_String (Value : Safe_String) return String is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value.Data = null then" & ASCII.LF
     & "         return """";" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return Value.Data.all;" & ASCII.LF
     & "   end To_String;" & ASCII.LF
     & ASCII.LF
     & "   function Length (Value : Safe_String) return Natural is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value.Data = null then" & ASCII.LF
     & "         return 0;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return Value.Data'Length;" & ASCII.LF
     & "   end Length;" & ASCII.LF
     & ASCII.LF
     & "   function Slice (Value : Safe_String; Low, High : Natural) return Safe_String is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value.Data = null" & ASCII.LF
     & "        or else Low = 0" & ASCII.LF
     & "        or else High = 0" & ASCII.LF
     & "        or else High < Low" & ASCII.LF
     & "        or else Low > Value.Data'Length" & ASCII.LF
     & "        or else High > Value.Data'Length" & ASCII.LF
     & "      then" & ASCII.LF
     & "         return Empty;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return From_Literal (Value.Data (Positive (Low) .. Positive (High)));" & ASCII.LF
     & "   end Slice;" & ASCII.LF
     & ASCII.LF
     & "   function Concat (Left, Right : Safe_String) return Safe_String is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      return From_Literal (To_String (Left) & To_String (Right));" & ASCII.LF
     & "   end Concat;" & ASCII.LF
     & ASCII.LF
     & "   function Equal (Left, Right : Safe_String) return Boolean is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      return To_String (Left) = To_String (Right);" & ASCII.LF
     & "   end Equal;" & ASCII.LF
     & "end Safe_String_RT;" & ASCII.LF;

   Array_RT_Spec_Template : constant String :=
     "pragma SPARK_Mode (On);" & ASCII.LF
     & ASCII.LF
     & "generic" & ASCII.LF
     & "   type Element_Type is private;" & ASCII.LF
     & "   with function Default_Element return Element_Type;" & ASCII.LF
     & "   with function Clone_Element (Source : Element_Type) return Element_Type;" & ASCII.LF
     & "   with procedure Free_Element (Value : in out Element_Type);" & ASCII.LF
     & "package Safe_Array_RT is" & ASCII.LF
     & "   type Safe_Array is private;" & ASCII.LF
     & "   type Element_Array is array (Positive range <>) of Element_Type;" & ASCII.LF
     & ASCII.LF
     & "   Empty : constant Safe_Array;" & ASCII.LF
     & ASCII.LF
     & "   function From_Array (Value : Element_Array) return Safe_Array" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (From_Array'Result => Value);" & ASCII.LF
     & "   function Clone (Source : Safe_Array) return Safe_Array" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Clone'Result => Source);" & ASCII.LF
     & "   procedure Copy (Target : in out Safe_Array; Source : Safe_Array)" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Target => (Target, Source));" & ASCII.LF
     & "   procedure Free (Value : in out Safe_Array)" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Value => Value);" & ASCII.LF
     & ASCII.LF
     & "   function Length (Value : Safe_Array) return Natural" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Length'Result => Value);" & ASCII.LF
     & "   function Element (Value : Safe_Array; Index : Positive) return Element_Type" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Element'Result => (Value, Index));" & ASCII.LF
     & "   function Slice (Value : Safe_Array; Low, High : Natural) return Safe_Array" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Slice'Result => (Value, Low, High));" & ASCII.LF
     & "   function Concat (Left, Right : Safe_Array) return Safe_Array" & ASCII.LF
     & "      with Global => null," & ASCII.LF
     & "           Depends => (Concat'Result => (Left, Right));" & ASCII.LF
     & ASCII.LF
     & "private" & ASCII.LF
     & "   pragma SPARK_Mode (Off);" & ASCII.LF
     & "   type Element_Array_Access is access Element_Array;" & ASCII.LF
     & "   type Safe_Array is record" & ASCII.LF
     & "      Data : Element_Array_Access := null;" & ASCII.LF
     & "   end record;" & ASCII.LF
     & "   Empty : constant Safe_Array := (Data => null);" & ASCII.LF
     & "end Safe_Array_RT;" & ASCII.LF;

   Array_RT_Body_Template : constant String :=
     "with Ada.Unchecked_Deallocation;" & ASCII.LF
     & ASCII.LF
     & "package body Safe_Array_RT is" & ASCII.LF
     & "   pragma SPARK_Mode (Off);" & ASCII.LF
     & "   procedure Free_Array is new Ada.Unchecked_Deallocation (Element_Array, Element_Array_Access);" & ASCII.LF
     & ASCII.LF
     & "   function From_Array (Value : Element_Array) return Safe_Array is" & ASCII.LF
     & "      Result : Safe_Array := Empty;" & ASCII.LF
     & "      Target_Index : Positive := 1;" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value'Length = 0 then" & ASCII.LF
     & "         return Empty;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      Result.Data := new Element_Array (1 .. Value'Length);" & ASCII.LF
     & "      for Index in Value'Range loop" & ASCII.LF
     & "         Result.Data (Target_Index) := Clone_Element (Value (Index));" & ASCII.LF
     & "         if Target_Index < Result.Data'Last then" & ASCII.LF
     & "            Target_Index := Target_Index + 1;" & ASCII.LF
     & "         end if;" & ASCII.LF
     & "      end loop;" & ASCII.LF
     & "      return Result;" & ASCII.LF
     & "   end From_Array;" & ASCII.LF
     & ASCII.LF
     & "   function Clone (Source : Safe_Array) return Safe_Array is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Source.Data = null then" & ASCII.LF
     & "         return Empty;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return From_Array (Source.Data.all);" & ASCII.LF
     & "   end Clone;" & ASCII.LF
     & ASCII.LF
     & "   procedure Copy (Target : in out Safe_Array; Source : Safe_Array) is" & ASCII.LF
     & "      Snapshot : constant Safe_Array := Clone (Source);" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      Free (Target);" & ASCII.LF
     & "      Target := Snapshot;" & ASCII.LF
     & "   end Copy;" & ASCII.LF
     & ASCII.LF
     & "   procedure Free (Value : in out Safe_Array) is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value.Data /= null then" & ASCII.LF
     & "         for Index in Value.Data'Range loop" & ASCII.LF
     & "            Free_Element (Value.Data (Index));" & ASCII.LF
     & "         end loop;" & ASCII.LF
     & "         Free_Array (Value.Data);" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      Value := Empty;" & ASCII.LF
     & "   end Free;" & ASCII.LF
     & ASCII.LF
     & "   function Length (Value : Safe_Array) return Natural is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value.Data = null then" & ASCII.LF
     & "         return 0;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return Value.Data'Length;" & ASCII.LF
     & "   end Length;" & ASCII.LF
     & ASCII.LF
     & "   function Element (Value : Safe_Array; Index : Positive) return Element_Type is" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      return Clone_Element (Value.Data (Index));" & ASCII.LF
     & "   end Element;" & ASCII.LF
     & ASCII.LF
     & "   function Slice (Value : Safe_Array; Low, High : Natural) return Safe_Array is" & ASCII.LF
     & "      Result : Safe_Array := Empty;" & ASCII.LF
     & "      Offset : Natural := 0;" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Value.Data = null" & ASCII.LF
     & "        or else Low = 0" & ASCII.LF
     & "        or else High = 0" & ASCII.LF
     & "        or else High < Low" & ASCII.LF
     & "        or else Low > Value.Data'Length" & ASCII.LF
     & "        or else High > Value.Data'Length" & ASCII.LF
     & "      then" & ASCII.LF
     & "         return Empty;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      Result.Data := new Element_Array (1 .. Positive (High - Low + 1));" & ASCII.LF
     & "      for Index in Positive (Low) .. Positive (High) loop" & ASCII.LF
     & "         Offset := Offset + 1;" & ASCII.LF
     & "         Result.Data (Positive (Offset)) := Clone_Element (Value.Data (Index));" & ASCII.LF
     & "      end loop;" & ASCII.LF
     & "      return Result;" & ASCII.LF
     & "   end Slice;" & ASCII.LF
     & ASCII.LF
     & "   function Concat (Left, Right : Safe_Array) return Safe_Array is" & ASCII.LF
     & "      Result : Safe_Array := Empty;" & ASCII.LF
     & "      Offset : Natural := 0;" & ASCII.LF
     & "   begin" & ASCII.LF
     & "      if Length (Left) + Length (Right) = 0 then" & ASCII.LF
     & "         return Empty;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      Result.Data := new Element_Array (1 .. Positive (Length (Left) + Length (Right)));" & ASCII.LF
     & "      if Left.Data /= null then" & ASCII.LF
     & "         for Index in Left.Data'Range loop" & ASCII.LF
     & "            Offset := Offset + 1;" & ASCII.LF
     & "            Result.Data (Positive (Offset)) := Clone_Element (Left.Data (Index));" & ASCII.LF
     & "         end loop;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      if Right.Data /= null then" & ASCII.LF
     & "         for Index in Right.Data'Range loop" & ASCII.LF
     & "            Offset := Offset + 1;" & ASCII.LF
     & "            Result.Data (Positive (Offset)) := Clone_Element (Right.Data (Index));" & ASCII.LF
     & "         end loop;" & ASCII.LF
     & "      end if;" & ASCII.LF
     & "      return Result;" & ASCII.LF
     & "   end Concat;" & ASCII.LF
     & "end Safe_Array_RT;" & ASCII.LF;

   Bounded_String_Spec_Template : constant String :=
     "pragma SPARK_Mode (On);" & ASCII.LF
     & ASCII.LF
     & "package Safe_Bounded_Strings" & ASCII.LF
     & "  with Pure" & ASCII.LF
     & "is" & ASCII.LF
     & "   generic" & ASCII.LF
     & "      Capacity : Positive;" & ASCII.LF
     & "   package Generic_Bounded_String" & ASCII.LF
     & "     with SPARK_Mode => On" & ASCII.LF
     & "   is" & ASCII.LF
     & "      type Bounded_String is private;" & ASCII.LF
     & ASCII.LF
     & "      Empty : constant Bounded_String;" & ASCII.LF
     & ASCII.LF
     & "      function To_Bounded (Value : String) return Bounded_String" & ASCII.LF
     & "        with Pre => Value'Length <= Capacity;" & ASCII.LF
     & ASCII.LF
     & "      function To_String (Value : Bounded_String) return String;" & ASCII.LF
     & ASCII.LF
     & "      function Length (Value : Bounded_String) return Natural;" & ASCII.LF
     & ASCII.LF
     & "      function ""="" (Left, Right : Bounded_String) return Boolean;" & ASCII.LF
     & "      function ""="" (Left : Bounded_String; Right : String) return Boolean;" & ASCII.LF
     & "      function ""="" (Left : String; Right : Bounded_String) return Boolean;" & ASCII.LF
     & ASCII.LF
     & "   private" & ASCII.LF
     & "      type Bounded_String is record" & ASCII.LF
     & "         Data   : String (1 .. Capacity) := (others => ' ');" & ASCII.LF
     & "         Length : Natural range 0 .. Capacity := 0;" & ASCII.LF
     & "      end record;" & ASCII.LF
     & ASCII.LF
     & "      Empty : constant Bounded_String :=" & ASCII.LF
     & "        (Data => (others => ' '), Length => 0);" & ASCII.LF
     & "   end Generic_Bounded_String;" & ASCII.LF
     & "end Safe_Bounded_Strings;" & ASCII.LF;

   Bounded_String_Body_Template : constant String :=
     "pragma SPARK_Mode (On);" & ASCII.LF
     & ASCII.LF
     & "package body Safe_Bounded_Strings is" & ASCII.LF
     & "   package body Generic_Bounded_String is" & ASCII.LF
     & "      function To_Bounded (Value : String) return Bounded_String is" & ASCII.LF
     & "         Result : Bounded_String := Empty;" & ASCII.LF
     & "      begin" & ASCII.LF
     & "         Result.Length := Value'Length;" & ASCII.LF
     & "         if Value'Length > 0 then" & ASCII.LF
     & "            Result.Data (1 .. Value'Length) := Value;" & ASCII.LF
     & "         end if;" & ASCII.LF
     & "         return Result;" & ASCII.LF
     & "      end To_Bounded;" & ASCII.LF
     & ASCII.LF
     & "      function To_String (Value : Bounded_String) return String is" & ASCII.LF
     & "      begin" & ASCII.LF
     & "         if Value.Length = 0 then" & ASCII.LF
     & "            return """";" & ASCII.LF
     & "         end if;" & ASCII.LF
     & "         return Value.Data (1 .. Value.Length);" & ASCII.LF
     & "      end To_String;" & ASCII.LF
     & ASCII.LF
     & "      function Length (Value : Bounded_String) return Natural is" & ASCII.LF
     & "      begin" & ASCII.LF
     & "         return Value.Length;" & ASCII.LF
     & "      end Length;" & ASCII.LF
     & ASCII.LF
     & "      function ""="" (Left, Right : Bounded_String) return Boolean is" & ASCII.LF
     & "      begin" & ASCII.LF
     & "         return To_String (Left) = To_String (Right);" & ASCII.LF
     & "      end ""="" ;" & ASCII.LF
     & ASCII.LF
     & "      function ""="" (Left : Bounded_String; Right : String) return Boolean is" & ASCII.LF
     & "      begin" & ASCII.LF
     & "         return To_String (Left) = Right;" & ASCII.LF
     & "      end ""="" ;" & ASCII.LF
     & ASCII.LF
     & "      function ""="" (Left : String; Right : Bounded_String) return Boolean is" & ASCII.LF
     & "      begin" & ASCII.LF
     & "         return Left = To_String (Right);" & ASCII.LF
     & "      end ""="" ;" & ASCII.LF
     & "   end Generic_Bounded_String;" & ASCII.LF
     & "end Safe_Bounded_Strings;" & ASCII.LF;

   Gnat_Adc_Contents : constant String :=
     "pragma Partition_Elaboration_Policy(Sequential);" & ASCII.LF
     & "pragma Profile(Jorvik);" & ASCII.LF;

   Safe_IO_Support_Marker : constant String :=
     "--  Generated Safe print support";

   type Cleanup_Action is (Cleanup_Deallocate, Cleanup_Reset_Null);

   type Cleanup_Item is record
      Action    : Cleanup_Action := Cleanup_Deallocate;
      Name      : FT.UString := FT.To_UString ("");
      Type_Name : FT.UString := FT.To_UString ("");
      Free_Proc : FT.UString := FT.To_UString ("");
      Is_Constant : Boolean := False;
   end record;

   package Cleanup_Item_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Cleanup_Item);

   type Cleanup_Frame is record
      Items : Cleanup_Item_Vectors.Vector;
   end record;

   package Cleanup_Frame_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Cleanup_Frame);

   type Type_Binding is record
      Name      : FT.UString := FT.To_UString ("");
      Type_Info : GM.Type_Descriptor;
   end record;

   package Type_Binding_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Binding);

   type Type_Binding_Frame is record
      Bindings : Type_Binding_Vectors.Vector;
   end record;

   package Type_Binding_Frame_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Binding_Frame);

   type Emit_State is record
      Needs_Safe_IO : Boolean := False;
      Needs_Safe_Runtime : Boolean := False;
      Needs_Safe_String_RT : Boolean := False;
      Needs_Safe_Array_RT  : Boolean := False;
      Needs_Safe_Bounded_Strings : Boolean := False;
      Needs_Ada_Strings_Unbounded : Boolean := False;
      Needs_Unevaluated_Use_Of_Old : Boolean := False;
      Needs_Gnat_Adc     : Boolean := False;
      Needs_Unchecked_Deallocation : Boolean := False;
      Wide_Local_Names   : FT.UString_Vectors.Vector;
      Bounded_String_Bounds : FT.UString_Vectors.Vector;
      Type_Binding_Stack : Type_Binding_Frame_Vectors.Vector;
      Unsupported_Span   : FT.Source_Span := FT.Null_Span;
      Unsupported_Message : FT.UString := FT.To_UString ("");
      Cleanup_Stack      : Cleanup_Frame_Vectors.Vector;
      Task_Body_Depth    : Natural := 0;
   end record;

   procedure Raise_Internal (Message : String);
   pragma No_Return (Raise_Internal);
   procedure Raise_Unsupported
     (State   : in out Emit_State;
      Span    : FT.Source_Span;
      Message : String);
   pragma No_Return (Raise_Unsupported);

   function Has_Text (Item : FT.UString) return Boolean;
   function Trim_Image (Value : Long_Long_Integer) return String;
   function Trim_Wide_Image (Value : CM.Wide_Integer) return String;
   function Indentation (Depth : Natural) return String;
   procedure Append_Line
     (Buffer : in out SU.Unbounded_String;
      Text   : String := "";
      Depth  : Natural := 0);
   function Join_Names (Items : FT.UString_Vectors.Vector) return String;
   function Contains_Name
     (Items : FT.UString_Vectors.Vector;
      Name  : String) return Boolean;
   procedure Add_Wide_Name
     (State : in out Emit_State;
      Name  : String);
   function Is_Wide_Name
     (State : Emit_State;
      Name  : String) return Boolean;
   function Names_Use_Wide_Storage
     (State : Emit_State;
      Names : FT.UString_Vectors.Vector) return Boolean;
   procedure Restore_Wide_Names
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type);
   procedure Push_Type_Binding_Frame (State : in out Emit_State);
   procedure Pop_Type_Binding_Frame (State : in out Emit_State);
   procedure Add_Type_Binding
     (State     : in out Emit_State;
      Name      : String;
      Type_Info : GM.Type_Descriptor);
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector);
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector);
   procedure Register_Param_Type_Bindings
     (State  : in out Emit_State;
      Params  : CM.Symbol_Vectors.Vector);
   function Lookup_Bound_Type
     (State     : Emit_State;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   procedure Push_Cleanup_Frame (State : in out Emit_State);
   procedure Pop_Cleanup_Frame (State : in out Emit_State);
   procedure Add_Cleanup_Item
     (State     : in out Emit_State;
      Name      : String;
      Type_Name : String;
      Free_Proc : String := "";
      Is_Constant : Boolean := False;
      Action    : Cleanup_Action := Cleanup_Deallocate);
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector);
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector);
   procedure Render_Cleanup_Item
     (Buffer : in out SU.Unbounded_String;
      Item   : Cleanup_Item;
      Depth  : Natural);
   procedure Render_Active_Cleanup
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural;
      Skip_Name : String := "");
   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural);
   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean;
   function Starts_With (Text : String; Prefix : String) return Boolean;
   function Ada_Safe_Name (Name : String) return String;
   function Sanitized_Helper_Name (Name : String) return String;
   function Normalize_Aspect_Name
     (Subprogram_Name : String;
      Raw_Name        : String) return String;
   function Is_Attribute_Selector (Name : String) return Boolean;
   function Root_Name (Expr : CM.Expr_Access) return String;
   function Expr_Uses_Name
     (Expr : CM.Expr_Access;
      Name : String) return Boolean;
   function Statements_Use_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean;
   function Selector_Is_Record_Field
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : CM.Expr_Access;
      Selector  : String) return Boolean;
   function Is_Aspect_State_Name (Name : String) return Boolean;
   function Is_Constant_Object_Name
     (Unit : CM.Resolved_Unit;
      Name : String) return Boolean;

   function Lookup_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return GM.Type_Descriptor;
   function Base_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return GM.Type_Descriptor;
   function Has_Type
     (Unit     : CM.Resolved_Unit;
     Document : GM.Mir_Document;
     Name     : String) return Boolean;
   function Type_Info_From_Name
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Lookup_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Span_Contains
     (Outer : FT.Source_Span;
      Inner : FT.Source_Span) return Boolean;
   function Lookup_Mir_Local_Type
     (Document  : GM.Mir_Document;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Lookup_Local_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Lookup_Selected_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : GM.Type_Descriptor;
      Selector  : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Resolve_Print_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      State     : Emit_State;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Positive;
   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Positive;
   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Array_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Tuple_Type (Info : GM.Type_Descriptor) return Boolean;
   function Is_Result_Builtin (Info : GM.Type_Descriptor) return Boolean;
   function Render_Result_Empty_Aggregate return String;
   function Render_Result_Fail_Aggregate (Message_Image : String) return String;
   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean;
   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean;
   function Is_Alias_Access (Info : GM.Type_Descriptor) return Boolean;
   function Needs_Implicit_Dereference
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean;
   function Is_String_Type_Name (Name : String) return Boolean;
   function Is_Bounded_String_Type (Info : GM.Type_Descriptor) return Boolean;
   function Bounded_String_Instance_Name (Bound : Natural) return String;
   function Bounded_String_Instance_Name (Info : GM.Type_Descriptor) return String;
   function Bounded_String_Type_Name (Bound : Natural) return String;
   function Bounded_String_Type_Name (Info : GM.Type_Descriptor) return String;
   function Synthetic_Bounded_String_Type
     (Name  : String;
      Found : out Boolean) return GM.Type_Descriptor;
   procedure Register_Bounded_String_Type
     (State : in out Emit_State;
      Info  : GM.Type_Descriptor);
   procedure Collect_Bounded_String_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State);
   procedure Append_Bounded_String_Instantiations
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State);
   procedure Append_Bounded_String_Uses
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural);
   function Expr_Type_Info
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return GM.Type_Descriptor;
   function Try_Static_Integer_Value
     (Expr  : CM.Expr_Access;
      Value : out Long_Long_Integer) return Boolean;
   function Fixed_Array_Cardinality
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Info : GM.Type_Descriptor;
      Cardinality : out Natural) return Boolean;
   function Static_Growable_Length
     (Expr   : CM.Expr_Access;
      Length : out Natural) return Boolean;
   function Render_Fixed_Array_As_Growable
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Render_Growable_As_Fixed
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Render_Growable_Array_Expr
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Render_Heap_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Expr_For_Target_Type
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Tuple_Field_Name (Index : Positive) return String;
   function Tuple_String_Discriminant_Name (Index : Positive) return String;
   function Render_Positional_Tuple_Aggregate
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Scalar_Value (Value : GM.Scalar_Value) return String;
   function Render_Record_Aggregate_For_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      Type_Info : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_String_Length_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Default_Value_Expr (Type_Name : String) return String;
   function Default_Value_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Default_Value_Expr (Info : GM.Type_Descriptor) return String;
   function Binary_Ada_Name (Bit_Width : Positive) return String;
   function Render_Type_Name (Info : GM.Type_Descriptor) return String;
   function Render_Subtype_Indication
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Render_Param_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Render_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return String;
   function Render_Object_Decl_Text_Common
     (Unit           : CM.Resolved_Unit;
      Document       : GM.Mir_Document;
      State          : in out Emit_State;
      Names          : FT.UString_Vectors.Vector;
      Type_Info      : GM.Type_Descriptor;
      Is_Constant    : Boolean;
      Has_Initializer : Boolean;
      Has_Implicit_Default_Init : Boolean;
      Initializer    : CM.Expr_Access;
      Local_Context  : Boolean := False) return String;
   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl;
   function Render_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   procedure Render_Growable_Array_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State);
   procedure Collect_Owner_Access_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector);
   procedure Render_Owner_Access_Helper_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor);
   procedure Render_Owner_Access_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State);
   procedure Collect_Synthetic_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector);
   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Resolved_Object_Decl;
      Local_Context : Boolean := False) return String;
   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Object_Decl;
      Local_Context : Boolean := False) return String;

   function Render_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Print_Argument
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Float_Convex_Combination
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Wide_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Uses_Wide_Value
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Expr     : CM.Expr_Access) return Boolean;
   function Render_Channel_Send_Value
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Expr : CM.Expr_Access;
      Value        : CM.Expr_Access) return String;
   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector);
   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector);

   procedure Render_Statements
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False);
   procedure Render_Required_Statement_Suite
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False);
   function Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector;
   function Non_Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector;
   procedure Render_In_Out_Param_Stabilizers
     (Buffer     : in out SU.Unbounded_String;
      Subprogram : CM.Resolved_Subprogram;
      Depth      : Natural);
   function Statement_Falls_Through
     (Item : CM.Statement_Access) return Boolean;
   function Statements_Fall_Through
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Statement_Contains_Exit
     (Item : CM.Statement_Access) return Boolean;
   function Statements_Contain_Exit
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Loop_Variant_Image
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Condition : CM.Expr_Access;
      State     : in out Emit_State) return String;
   function Contains_Recursive_Accumulator_Pattern
     (Subprogram_Name : String;
      Local_Names     : FT.UString_Vectors.Vector;
      Statements      : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Uses_Structural_Traversal_Lowering
     (Subprogram : CM.Resolved_Subprogram) return Boolean;
   function Replace_Identifier_Token
     (Text        : String;
      Name        : String;
      Replacement : String) return String;
   procedure Append_Gnatprove_Warning_Suppression
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Reason  : String;
      Depth   : Natural);
   procedure Append_Gnatprove_Warning_Restore
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Depth   : Natural);
   procedure Append_Initialization_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Initialization_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Assignment_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Assignment_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_If_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_If_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Channel_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Channel_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   function Structural_Accumulator_Count_Total_Bound
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Count_Name : String;
      Total_Name : String;
      State      : in out Emit_State) return String;

   function Render_Subprogram_Params
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Params     : CM.Symbol_Vectors.Vector) return String;
   function Render_Ada_Subprogram_Keyword
     (Subprogram : CM.Resolved_Subprogram) return String;
   function Render_Subprogram_Return
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram) return String;
   function Render_Initializes_Aspect
     (Unit   : CM.Resolved_Unit;
      Bronze : MB.Bronze_Result) return String;
   function Render_Access_Param_Precondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String;
   function Render_Access_Param_Postcondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String;
   function Exprs_Match
     (Left  : CM.Expr_Access;
      Right : CM.Expr_Access) return Boolean;
   function Expr_Contains_Target
     (Expr   : CM.Expr_Access;
      Target : CM.Expr_Access) return Boolean;
   function Render_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String;
   function Render_Expr_With_Old_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String;
   function Render_Wide_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String;
   function Render_Subprogram_Aspects
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Bronze     : MB.Bronze_Result;
      State      : in out Emit_State) return String;
   procedure Render_Channel_Spec
     (Buffer  : in out SU.Unbounded_String;
      Channel : CM.Resolved_Channel_Decl;
      Bronze  : MB.Bronze_Result);
   procedure Render_Channel_Body
     (Buffer  : in out SU.Unbounded_String;
      Channel : CM.Resolved_Channel_Decl);
   procedure Render_Free_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural);
   procedure Render_Free_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural);
   procedure Render_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State);
   procedure Render_Task_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Task_Item : CM.Resolved_Task;
      State    : in out Emit_State);

   function Safe_Runtime_Text return String is
     (Runtime_Template);

   function Safe_String_RT_Spec_Text return String is
     (String_RT_Spec_Template);

   function Safe_String_RT_Body_Text return String is
     (String_RT_Body_Template);

   function Safe_Array_RT_Spec_Text return String is
     (Array_RT_Spec_Template);

   function Safe_Array_RT_Body_Text return String is
     (Array_RT_Body_Template);

   function Safe_Bounded_Strings_Spec_Text return String is
     (Bounded_String_Spec_Template);

   function Safe_Bounded_Strings_Body_Text return String is
     (Bounded_String_Body_Template);

   function Gnat_Adc_Text return String is
     (Gnat_Adc_Contents);

   procedure Raise_Internal (Message : String) is
   begin
      raise Emitter_Internal with Message;
   end Raise_Internal;

   procedure Raise_Unsupported
     (State   : in out Emit_State;
      Span    : FT.Source_Span;
      Message : String) is
   begin
      State.Unsupported_Span := Span;
      State.Unsupported_Message := FT.To_UString (Message);
      raise Emitter_Unsupported;
   end Raise_Unsupported;

   function Has_Text (Item : FT.UString) return Boolean is
   begin
      return FT.To_String (Item)'Length > 0;
   end Has_Text;

   function Trim_Image (Value : Long_Long_Integer) return String is
      Image : constant String := Long_Long_Integer'Image (Value);
   begin
      if Image'Length > 0 and then Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim_Image;

   function Trim_Wide_Image (Value : CM.Wide_Integer) return String is
      Image : constant String := CM.Wide_Integer'Image (Value);
   begin
      if Image'Length > 0 and then Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim_Wide_Image;

   function Is_Print_Call (Expr : CM.Expr_Access) return Boolean is
   begin
      return
        Expr /= null
        and then Expr.Kind = CM.Expr_Call
        and then FT.Lowercase (CM.Flatten_Name (Expr.Callee)) = "print";
   end Is_Print_Call;

   function Statements_Use_Print
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
   is
   begin
      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Call =>
                  if Is_Print_Call (Item.Call) then
                     return True;
                  end if;
               when CM.Stmt_If =>
                  if Statements_Use_Print (Item.Then_Stmts) then
                     return True;
                  end if;
                  for Part of Item.Elsifs loop
                     if Statements_Use_Print (Part.Statements) then
                        return True;
                     end if;
                  end loop;
                  if Item.Has_Else and then Statements_Use_Print (Item.Else_Stmts) then
                     return True;
                  end if;
               when CM.Stmt_Case =>
                  for Arm of Item.Case_Arms loop
                     if Statements_Use_Print (Arm.Statements) then
                        return True;
                     end if;
                  end loop;
               when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                  if Statements_Use_Print (Item.Body_Stmts) then
                     return True;
                  end if;
               when CM.Stmt_Select =>
                  for Arm of Item.Arms loop
                     case Arm.Kind is
                        when CM.Select_Arm_Channel =>
                           if Statements_Use_Print (Arm.Channel_Data.Statements) then
                              return True;
                           end if;
                        when CM.Select_Arm_Delay =>
                           if Statements_Use_Print (Arm.Delay_Data.Statements) then
                              return True;
                           end if;
                        when others =>
                           null;
                     end case;
                  end loop;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      return False;
   end Statements_Use_Print;

   function Indentation (Depth : Natural) return String is
   begin
      if Depth = 0 then
         return "";
      end if;
      return (1 .. Depth * Indent_Width => ' ');
   end Indentation;

   procedure Append_Line
     (Buffer : in out SU.Unbounded_String;
      Text   : String := "";
      Depth  : Natural := 0) is
   begin
      Buffer :=
        Buffer
        & SU.To_Unbounded_String (Indentation (Depth) & Text & ASCII.LF);
   end Append_Line;

   function Join_Names (Items : FT.UString_Vectors.Vector) return String is
      Result : SU.Unbounded_String;
      First  : Boolean := True;
   begin
      for Item of Items loop
         if not First then
            Result := Result & SU.To_Unbounded_String (", ");
         else
            First := False;
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Item));
      end loop;
      return SU.To_String (Result);
   end Join_Names;

   function Contains_Name
     (Items : FT.UString_Vectors.Vector;
      Name  : String) return Boolean is
   begin
      for Item of Items loop
         if FT.To_String (Item) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Name;

   procedure Add_Wide_Name
     (State : in out Emit_State;
      Name  : String) is
   begin
      pragma Unreferenced (State, Name);
   end Add_Wide_Name;

   function Is_Wide_Name
     (State : Emit_State;
      Name  : String) return Boolean is
   begin
      pragma Unreferenced (State, Name);
      return False;
   end Is_Wide_Name;

   function Names_Use_Wide_Storage
     (State : Emit_State;
      Names : FT.UString_Vectors.Vector) return Boolean is
   begin
      pragma Unreferenced (State, Names);
      return False;
   end Names_Use_Wide_Storage;

   procedure Restore_Wide_Names
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) is
   begin
      while State.Wide_Local_Names.Length > Previous_Length loop
         State.Wide_Local_Names.Delete_Last;
      end loop;
   end Restore_Wide_Names;

   procedure Push_Type_Binding_Frame (State : in out Emit_State) is
   begin
      State.Type_Binding_Stack.Append ((Bindings => <>));
   end Push_Type_Binding_Frame;

   procedure Pop_Type_Binding_Frame (State : in out Emit_State) is
   begin
      if State.Type_Binding_Stack.Is_Empty then
         Raise_Internal ("type binding frame stack underflow during Ada emission");
      end if;
      State.Type_Binding_Stack.Delete_Last;
   end Pop_Type_Binding_Frame;

   procedure Add_Type_Binding
     (State     : in out Emit_State;
      Name      : String;
      Type_Info : GM.Type_Descriptor) is
   begin
      if State.Type_Binding_Stack.Is_Empty then
         Raise_Internal ("type binding added outside an active binding scope during Ada emission");
      end if;

      declare
         Frame : Type_Binding_Frame := State.Type_Binding_Stack.Last_Element;
      begin
         Frame.Bindings.Append
           ((Name      => FT.To_UString (Name),
             Type_Info => Type_Info));
         State.Type_Binding_Stack.Replace_Element (State.Type_Binding_Stack.Last_Index, Frame);
      end;
   end Add_Type_Binding;

   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         for Name of Decl.Names loop
            Add_Type_Binding (State, FT.To_String (Name), Decl.Type_Info);
         end loop;
      end loop;
   end Register_Type_Bindings;

   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         for Name of Decl.Names loop
            Add_Type_Binding (State, FT.To_String (Name), Decl.Type_Info);
         end loop;
      end loop;
   end Register_Type_Bindings;

   procedure Register_Param_Type_Bindings
     (State  : in out Emit_State;
      Params  : CM.Symbol_Vectors.Vector) is
   begin
      for Param of Params loop
         Add_Type_Binding (State, FT.To_String (Param.Name), Param.Type_Info);
      end loop;
   end Register_Param_Type_Bindings;

   function Lookup_Bound_Type
     (State     : Emit_State;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
   begin
      if Name'Length = 0 or else State.Type_Binding_Stack.Is_Empty then
         return False;
      end if;

      for Frame_Index in reverse State.Type_Binding_Stack.First_Index .. State.Type_Binding_Stack.Last_Index loop
         declare
            Frame : constant Type_Binding_Frame := State.Type_Binding_Stack (Frame_Index);
         begin
            if not Frame.Bindings.Is_Empty then
               for Binding_Index in reverse Frame.Bindings.First_Index .. Frame.Bindings.Last_Index loop
                  declare
                     Binding : constant Type_Binding := Frame.Bindings (Binding_Index);
                  begin
                     if FT.To_String (Binding.Name) = Name then
                        Type_Info := Binding.Type_Info;
                        return True;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      return False;
   end Lookup_Bound_Type;

   procedure Push_Cleanup_Frame (State : in out Emit_State) is
   begin
      State.Cleanup_Stack.Append ((Items => <>));
   end Push_Cleanup_Frame;

   procedure Pop_Cleanup_Frame (State : in out Emit_State) is
   begin
      if State.Cleanup_Stack.Is_Empty then
         Raise_Internal ("cleanup frame stack underflow during Ada emission");
      end if;
      State.Cleanup_Stack.Delete_Last;
   end Pop_Cleanup_Frame;

   procedure Add_Cleanup_Item
     (State     : in out Emit_State;
      Name      : String;
      Type_Name : String;
      Free_Proc : String := "";
      Is_Constant : Boolean := False;
      Action    : Cleanup_Action := Cleanup_Deallocate) is
   begin
      if State.Cleanup_Stack.Is_Empty then
         Raise_Internal ("cleanup item added outside an active cleanup scope during Ada emission");
      end if;

      declare
         Frame : Cleanup_Frame := State.Cleanup_Stack.Last_Element;
      begin
         Frame.Items.Append
           ((Action    => Action,
             Name      => FT.To_UString (Name),
             Type_Name => FT.To_UString (Type_Name),
             Free_Proc => FT.To_UString (Free_Proc),
             Is_Constant => Is_Constant));
         State.Cleanup_Stack.Replace_Element (State.Cleanup_Stack.Last_Index, Frame);
      end;
   end Add_Cleanup_Item;

   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         if Is_Owner_Access (Decl.Type_Info) then
            for Name of Decl.Names loop
               Add_Cleanup_Item
                 (State,
                  FT.To_String (Name),
                  FT.To_String (Decl.Type_Info.Name),
                  Is_Constant => False);
            end loop;
         end if;
      end loop;
   end Register_Cleanup_Items;

   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         if Is_Owner_Access (Decl.Type_Info) then
            for Name of Decl.Names loop
               Add_Cleanup_Item
                 (State,
                  FT.To_String (Name),
                  FT.To_String (Decl.Type_Info.Name),
                  Is_Constant => False);
            end loop;
         end if;
      end loop;
   end Register_Cleanup_Items;

   procedure Render_Cleanup_Item
     (Buffer : in out SU.Unbounded_String;
      Item   : Cleanup_Item;
      Depth  : Natural) is
      Free_Call : constant String :=
        (if Item.Is_Constant and then not Has_Text (Item.Free_Proc)
         then "Dispose_" & Sanitized_Helper_Name (FT.To_String (Item.Type_Name))
         elsif Has_Text (Item.Free_Proc)
         then FT.To_String (Item.Free_Proc)
         else "Free_" & Sanitized_Helper_Name (FT.To_String (Item.Type_Name)));
   begin
      case Item.Action is
         when Cleanup_Deallocate =>
            if Item.Is_Constant then
               Append_Line (Buffer, "declare", Depth);
               Append_Line
                 (Buffer,
                  "Cleanup_Target : "
                  & FT.To_String (Item.Type_Name)
                  & " := "
                  & FT.To_String (Item.Name)
                  & ";",
                  Depth + 1);
               Append_Line (Buffer, "begin", Depth);
               Append_Line
                 (Buffer,
                  Free_Call & " (Cleanup_Target);",
                  Depth + 1);
               Append_Line (Buffer, "end;", Depth);
            else
               Append_Line
                 (Buffer,
                  Free_Call & " (" & FT.To_String (Item.Name) & ");",
                  Depth);
               if not Has_Text (Item.Free_Proc) then
                  Append_Line
                    (Buffer,
                     "pragma Assert (" & FT.To_String (Item.Name) & " = null);",
                     Depth);
               end if;
            end if;
         when Cleanup_Reset_Null =>
            Append_Line
              (Buffer,
               FT.To_String (Item.Name) & " := null;",
               Depth);
      end case;
   end Render_Cleanup_Item;

   procedure Render_Active_Cleanup
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural;
      Skip_Name : String := "") is
   begin
      if State.Cleanup_Stack.Is_Empty then
         return;
      end if;
      for Frame_Index in reverse State.Cleanup_Stack.First_Index .. State.Cleanup_Stack.Last_Index loop
         declare
            Frame : constant Cleanup_Frame := State.Cleanup_Stack (Frame_Index);
         begin
            for Item_Index in reverse Frame.Items.First_Index .. Frame.Items.Last_Index loop
               if Skip_Name'Length = 0
                 or else FT.To_String (Frame.Items (Item_Index).Name) /= Skip_Name
               then
                  Render_Cleanup_Item (Buffer, Frame.Items (Item_Index), Depth);
               end if;
            end loop;
         end;
      end loop;
   end Render_Active_Cleanup;

   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural) is
   begin
      if State.Cleanup_Stack.Is_Empty then
         return;
      end if;

      declare
         Frame : constant Cleanup_Frame := State.Cleanup_Stack.Last_Element;
      begin
         for Item_Index in reverse Frame.Items.First_Index .. Frame.Items.Last_Index loop
            Render_Cleanup_Item (Buffer, Frame.Items (Item_Index), Depth);
         end loop;
      end;
   end Render_Current_Cleanup_Frame;

   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean is
   begin
      if State.Cleanup_Stack.Is_Empty then
         return False;
      end if;

      for Frame of State.Cleanup_Stack loop
         if not Frame.Items.Is_Empty then
            return True;
         end if;
      end loop;
      return False;
   end Has_Active_Cleanup_Items;

   function Starts_With (Text : String; Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length
        and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Binary_Width_From_Name (Name : String) return Natural is
   begin
      if Name = "__binary_8" then
         return 8;
      elsif Name = "__binary_16" then
         return 16;
      elsif Name = "__binary_32" then
         return 32;
      elsif Name = "__binary_64" then
         return 64;
      end if;
      return 0;
   end Binary_Width_From_Name;

   function Binary_Ada_Name (Bit_Width : Positive) return String is
   begin
      return
        "Interfaces.Unsigned_"
        & Ada.Strings.Fixed.Trim (Positive'Image (Bit_Width), Ada.Strings.Both);
   end Binary_Ada_Name;

   function Ada_Safe_Name (Name : String) return String is
      Bit_Width : constant Natural := Binary_Width_From_Name (Name);
   begin
      if Bit_Width /= 0 then
         return Binary_Ada_Name (Positive (Bit_Width));
      elsif Name = "integer" then
         return "Long_Long_Integer";
      elsif Name = "boolean" then
         return "Boolean";
      elsif Name = "character" then
         return "Character";
      elsif Name = "string" then
         return "String";
      elsif Name = "float" then
         return "Float";
      elsif Name = "long_float" then
         return "Long_Float";
      elsif Name = "duration" then
         return "Duration";
      elsif Starts_With (Name, "__") then
         return "Safe_" & Name (Name'First + 2 .. Name'Last);
      elsif Name'Length > 0 and then Name (Name'First) = '_' then
         return "Safe" & Name;
      end if;
      return Name;
   end Ada_Safe_Name;

   function Normalize_Aspect_Name
     (Subprogram_Name : String;
      Raw_Name        : String) return String is
      Name_Image : constant String :=
        (if Raw_Name = "return"
         then Subprogram_Name & "'Result"
         elsif Starts_With (Raw_Name, "param:")
         then Raw_Name (Raw_Name'First + 6 .. Raw_Name'Last)
         elsif Starts_With (Raw_Name, "global:")
         then Raw_Name (Raw_Name'First + 7 .. Raw_Name'Last)
         else Raw_Name);
      Dot_Pos : Natural := 0;
   begin
      for Index in reverse Name_Image'Range loop
         if Name_Image (Index) = '.' then
            Dot_Pos := Index;
            exit;
         end if;
      end loop;

      if Dot_Pos > 0
        and then Dot_Pos < Name_Image'Last
        and then Is_Attribute_Selector (Name_Image (Dot_Pos + 1 .. Name_Image'Last))
      then
         return
           Name_Image (Name_Image'First .. Dot_Pos - 1)
           & "'"
           & Name_Image (Dot_Pos + 1 .. Name_Image'Last);
      end if;
      return Name_Image;
   end Normalize_Aspect_Name;

   function Is_Attribute_Selector (Name : String) return Boolean is
   begin
      return
        Name = "access"
        or else Name = "address"
        or else Name = "adjacent"
        or else Name = "aft"
        or else Name = "alignment"
        or else Name = "base"
        or else Name = "bit_order"
        or else Name = "ceiling"
        or else Name = "component_size"
        or else Name = "compose"
        or else Name = "constrained"
        or else Name = "copy_sign"
        or else Name = "definite"
        or else Name = "delta"
        or else Name = "denorm"
        or else Name = "digits"
        or else Name = "enum_rep"
        or else Name = "enum_val"
        or else Name = "exponent"
        or else Name = "first"
        or else Name = "first_valid"
        or else Name = "floor"
        or else Name = "fore"
        or else Name = "fraction"
        or else Name = "image"
        or else Name = "last"
        or else Name = "last_valid"
        or else Name = "leading_part"
        or else Name = "length"
        or else Name = "machine"
        or else Name = "machine_emax"
        or else Name = "machine_emin"
        or else Name = "machine_mantissa"
        or else Name = "machine_overflows"
        or else Name = "machine_radix"
        or else Name = "machine_rounds"
        or else Name = "max"
        or else Name = "max_alignment_for_allocation"
        or else Name = "max_size_in_storage_elements"
        or else Name = "min"
        or else Name = "mod"
        or else Name = "model"
        or else Name = "model_emin"
        or else Name = "model_epsilon"
        or else Name = "model_mantissa"
        or else Name = "model_small"
        or else Name = "modulus"
        or else Name = "object_size"
        or else Name = "overlaps_storage"
        or else Name = "pos"
        or else Name = "pred"
        or else Name = "range"
        or else Name = "remainder"
        or else Name = "round"
        or else Name = "rounding"
        or else Name = "safe_first"
        or else Name = "safe_last"
        or else Name = "scale"
        or else Name = "scaling"
        or else Name = "size"
        or else Name = "small"
        or else Name = "storage_size"
        or else Name = "succ"
        or else Name = "truncation"
        or else Name = "unbiased_rounding"
        or else Name = "val"
        or else Name = "valid"
        or else Name = "value"
        or else Name = "wide_image"
        or else Name = "wide_value"
        or else Name = "wide_wide_image"
        or else Name = "wide_wide_value"
        or else Name = "wide_wide_width"
        or else Name = "wide_width"
        or else Name = "width";
   end Is_Attribute_Selector;

   function Root_Name (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return FT.To_String (Expr.Name);
         when CM.Expr_Select | CM.Expr_Resolved_Index =>
            return Root_Name (Expr.Prefix);
         when others =>
            return "";
      end case;
   end Root_Name;

   function Expr_Uses_Name
     (Expr : CM.Expr_Access;
      Name : String) return Boolean
   is
   begin
      if Expr = null or else Name'Length = 0 then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return FT.To_String (Expr.Name) = Name;
         when CM.Expr_Select =>
            return Expr_Uses_Name (Expr.Prefix, Name);
         when CM.Expr_Resolved_Index =>
            if Expr_Uses_Name (Expr.Prefix, Name) then
               return True;
            end if;
            for Item of Expr.Args loop
               if Expr_Uses_Name (Item, Name) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Call =>
            if Expr_Uses_Name (Expr.Callee, Name) then
               return True;
            end if;
            for Item of Expr.Args loop
               if Expr_Uses_Name (Item, Name) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary =>
           return
              Expr_Uses_Name (Expr.Inner, Name)
              or else Expr_Uses_Name (Expr.Target, Name);
         when CM.Expr_Binary =>
            return
              Expr_Uses_Name (Expr.Left, Name)
              or else Expr_Uses_Name (Expr.Right, Name);
         when CM.Expr_Allocator =>
            return Expr_Uses_Name (Expr.Value, Name);
         when CM.Expr_Aggregate =>
            for Field of Expr.Fields loop
               if Expr_Uses_Name (Field.Expr, Name) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Uses_Name;

   function Statements_Use_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean
   is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Object_Decl =>
                  if Expr_Uses_Name (Item.Decl.Initializer, Name) then
                     return True;
                  end if;
               when CM.Stmt_Destructure_Decl =>
                  if Expr_Uses_Name (Item.Destructure.Initializer, Name) then
                     return True;
                  end if;
               when CM.Stmt_Assign =>
                  if Expr_Uses_Name (Item.Target, Name)
                    or else Expr_Uses_Name (Item.Value, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Call =>
                  if Expr_Uses_Name (Item.Call, Name) then
                     return True;
                  end if;
               when CM.Stmt_Return =>
                  if Expr_Uses_Name (Item.Value, Name) then
                     return True;
                  end if;
               when CM.Stmt_If =>
                  if Expr_Uses_Name (Item.Condition, Name)
                    or else Statements_Use_Name (Item.Then_Stmts, Name)
                  then
                     return True;
                  end if;
                  for Part of Item.Elsifs loop
                     if Expr_Uses_Name (Part.Condition, Name)
                       or else Statements_Use_Name (Part.Statements, Name)
                     then
                        return True;
                     end if;
                  end loop;
                  if Item.Has_Else
                    and then Statements_Use_Name (Item.Else_Stmts, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Case =>
                  if Expr_Uses_Name (Item.Case_Expr, Name) then
                     return True;
                  end if;
                  for Arm of Item.Case_Arms loop
                     if Expr_Uses_Name (Arm.Choice, Name)
                       or else Statements_Use_Name (Arm.Statements, Name)
                     then
                        return True;
                     end if;
                  end loop;
               when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                  if Expr_Uses_Name (Item.Condition, Name)
                    or else Expr_Uses_Name (Item.Loop_Range.Name_Expr, Name)
                    or else Expr_Uses_Name (Item.Loop_Range.Low_Expr, Name)
                    or else Expr_Uses_Name (Item.Loop_Range.High_Expr, Name)
                    or else Expr_Uses_Name (Item.Loop_Iterable, Name)
                    or else Statements_Use_Name (Item.Body_Stmts, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Exit =>
                  if Expr_Uses_Name (Item.Condition, Name) then
                     return True;
                  end if;
               when CM.Stmt_Send | CM.Stmt_Receive | CM.Stmt_Try_Send | CM.Stmt_Try_Receive =>
                  if Expr_Uses_Name (Item.Channel_Name, Name)
                    or else Expr_Uses_Name (Item.Value, Name)
                    or else Expr_Uses_Name (Item.Target, Name)
                    or else Expr_Uses_Name (Item.Success_Var, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Select =>
                  for Arm of Item.Arms loop
                     case Arm.Kind is
                        when CM.Select_Arm_Channel =>
                           if Expr_Uses_Name (Arm.Channel_Data.Channel_Name, Name)
                             or else Statements_Use_Name (Arm.Channel_Data.Statements, Name)
                           then
                              return True;
                           end if;
                        when CM.Select_Arm_Delay =>
                           if Expr_Uses_Name (Arm.Delay_Data.Duration_Expr, Name)
                             or else Statements_Use_Name (Arm.Delay_Data.Statements, Name)
                           then
                              return True;
                           end if;
                        when others =>
                           null;
                     end case;
                  end loop;
               when CM.Stmt_Delay =>
                  if Expr_Uses_Name (Item.Value, Name) then
                     return True;
                  end if;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      return False;
   end Statements_Use_Name;

   function Selector_Is_Record_Field
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : CM.Expr_Access;
      Selector  : String) return Boolean
   is
      Prefix_Type : GM.Type_Descriptor;
   begin
      if Prefix = null or else Selector'Length = 0 then
         return False;
      end if;

      if Prefix.Kind = CM.Expr_Select
        and then FT.To_String (Prefix.Selector) = "all"
        and then Prefix.Prefix /= null
        and then Has_Text (Prefix.Prefix.Type_Name)
      then
         Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Prefix.Prefix.Type_Name));
      elsif Has_Text (Prefix.Type_Name) then
         Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Prefix.Type_Name));
      else
         return False;
      end if;

      if not Has_Text (Prefix_Type.Name) then
         return False;
      end if;

      if Is_Access_Type (Prefix_Type) and then Has_Text (Prefix_Type.Target) then
         Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Prefix_Type.Target));
         if not Has_Text (Prefix_Type.Name) then
            return False;
         end if;
      end if;

      if FT.To_String (Prefix_Type.Kind) /= "record" then
         return False;
      end if;

      if Prefix_Type.Has_Discriminant
        and then FT.To_String (Prefix_Type.Discriminant_Name) = Selector
      then
         return True;
      end if;

      for Field of Prefix_Type.Fields loop
         if FT.To_String (Field.Name) = Selector then
            return True;
         end if;
      end loop;
      return False;
   end Selector_Is_Record_Field;

   function Is_Aspect_State_Name (Name : String) return Boolean is
   begin
      for Ch of Name loop
         if Ch = ''' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Aspect_State_Name;

   function Is_Constant_Object_Name
     (Unit : CM.Resolved_Unit;
      Name : String) return Boolean
   is
   begin
      for Decl of Unit.Objects loop
         if Decl.Is_Constant then
            for Object_Name of Decl.Names loop
               if FT.To_String (Object_Name) = Name then
                  return True;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Is_Constant_Object_Name;

   function Lookup_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return GM.Type_Descriptor
   is
   begin
      for Item of Unit.Types loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      for Item of Unit.Imported_Types loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      for Item of Document.Types loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Lookup_Type;

   function Is_Builtin_Integer_Name (Name : String) return Boolean is
   begin
      return Name in "integer" | "long_long_integer";
   end Is_Builtin_Integer_Name;

   function Is_Builtin_Binary_Name (Name : String) return Boolean is
   begin
      return Binary_Width_From_Name (Name) /= 0;
   end Is_Builtin_Binary_Name;

   function Is_Builtin_Float_Name (Name : String) return Boolean is
   begin
      return Name in "float" | "long_float";
   end Is_Builtin_Float_Name;

   function Base_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor := Info;
   begin
      while FT.To_String (Result.Kind) = "subtype"
        and then Result.Has_Base
        and then Has_Type (Unit, Document, FT.To_String (Result.Base))
      loop
         Result := Lookup_Type (Unit, Document, FT.To_String (Result.Base));
      end loop;
      return Result;
   end Base_Type;

   function Has_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean is
      Item : constant GM.Type_Descriptor := Lookup_Type (Unit, Document, Name);
   begin
      return Has_Text (Item.Name);
   end Has_Type;

   function Type_Info_From_Name
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Lower_Name : constant String := FT.Lowercase (Name);
   begin
      if Name'Length = 0 then
         return False;
      elsif Has_Type (Unit, Document, Name) then
         Type_Info := Lookup_Type (Unit, Document, Name);
         return True;
      elsif Lower_Name = "integer" or else Lower_Name = "long_long_integer" then
         Type_Info := BT.Integer_Type;
         return True;
      elsif Lower_Name = "boolean" then
         Type_Info := BT.Boolean_Type;
         return True;
      elsif Lower_Name = "string" then
         Type_Info := BT.String_Type;
         return True;
      elsif Lower_Name = "result" then
         Type_Info := BT.Result_Type;
         return True;
      elsif Is_Builtin_Binary_Name (Lower_Name) then
         Type_Info := BT.Binary_Type (Positive (Binary_Width_From_Name (Lower_Name)));
         return True;
      end if;

      return False;
   end Type_Info_From_Name;

   function Lookup_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
   begin
      for Decl of Unit.Objects loop
         for Object_Name of Decl.Names loop
            if FT.To_String (Object_Name) = Name then
               Type_Info := Decl.Type_Info;
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Lookup_Object_Type;

   function Span_Contains
     (Outer : FT.Source_Span;
      Inner : FT.Source_Span) return Boolean
   is
      function Before
        (Left  : FT.Source_Position;
         Right : FT.Source_Position) return Boolean is
      begin
         return Left.Line < Right.Line
           or else (Left.Line = Right.Line and then Left.Column < Right.Column);
      end Before;
   begin
      if (Outer.Start_Pos.Line = FT.Null_Span.Start_Pos.Line
          and then Outer.Start_Pos.Column = FT.Null_Span.Start_Pos.Column
          and then Outer.End_Pos.Line = FT.Null_Span.End_Pos.Line
          and then Outer.End_Pos.Column = FT.Null_Span.End_Pos.Column)
        or else
         (Inner.Start_Pos.Line = FT.Null_Span.Start_Pos.Line
          and then Inner.Start_Pos.Column = FT.Null_Span.Start_Pos.Column
          and then Inner.End_Pos.Line = FT.Null_Span.End_Pos.Line
          and then Inner.End_Pos.Column = FT.Null_Span.End_Pos.Column)
      then
         return False;
      end if;

      return
        not Before (Inner.Start_Pos, Outer.Start_Pos)
        and then not Before (Outer.End_Pos, Inner.End_Pos);
   end Span_Contains;

   function Lookup_Mir_Local_Type
     (Document  : GM.Mir_Document;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Graph of Document.Graphs loop
         if Graph.Has_Span and then Span_Contains (Graph.Span, Span) then
            for Local of Graph.Locals loop
               if FT.To_String (Local.Name) = Name then
                  Type_Info := Local.Type_Info;
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Lookup_Mir_Local_Type;

   function Lookup_Local_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      function Before
        (Left  : FT.Source_Position;
         Right : FT.Source_Position) return Boolean is
      begin
         return Left.Line < Right.Line
           or else (Left.Line = Right.Line and then Left.Column < Right.Column);
      end Before;

      function Starts_After_Use (Item_Span : FT.Source_Span) return Boolean is
      begin
         return
           not (Item_Span.Start_Pos.Line = FT.Null_Span.Start_Pos.Line
                and then Item_Span.Start_Pos.Column = FT.Null_Span.Start_Pos.Column
                and then Item_Span.End_Pos.Line = FT.Null_Span.End_Pos.Line
                and then Item_Span.End_Pos.Column = FT.Null_Span.End_Pos.Column)
           and then Before (Span.Start_Pos, Item_Span.Start_Pos);
      end Starts_After_Use;

      function Lookup_In_Decls
        (Decls : CM.Resolved_Object_Decl_Vectors.Vector) return Boolean is
      begin
         for Decl of Decls loop
            for Object_Name of Decl.Names loop
               if FT.To_String (Object_Name) = Name then
                  Type_Info := Decl.Type_Info;
                  return True;
               end if;
            end loop;
         end loop;
         return False;
      end Lookup_In_Decls;

      function Lookup_In_Decl
        (Decl : CM.Object_Decl) return Boolean is
      begin
         for Object_Name of Decl.Names loop
            if FT.To_String (Object_Name) = Name then
               Type_Info := Decl.Type_Info;
               return True;
            end if;
         end loop;
         return False;
      end Lookup_In_Decl;

      function Lookup_In_Statements
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
      is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            elsif Starts_After_Use (Item.Span) then
               return False;
            else
               if Item.Kind = CM.Stmt_Object_Decl and then Lookup_In_Decl (Item.Decl) then
                  return True;
               end if;

               if not Span_Contains (Item.Span, Span) then
                  null;
               else
                  case Item.Kind is
                     when CM.Stmt_Object_Decl =>
                        return Lookup_In_Decl (Item.Decl);
                     when CM.Stmt_If =>
                        if Lookup_In_Statements (Item.Then_Stmts) then
                           return True;
                        end if;
                        for Part of Item.Elsifs loop
                           if Lookup_In_Statements (Part.Statements) then
                              return True;
                           end if;
                        end loop;
                        if Item.Has_Else
                          and then Lookup_In_Statements (Item.Else_Stmts)
                        then
                           return True;
                        end if;
                        return False;
                     when CM.Stmt_Case =>
                        for Arm of Item.Case_Arms loop
                           if Lookup_In_Statements (Arm.Statements) then
                              return True;
                           end if;
                        end loop;
                        return False;
                     when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                        return Lookup_In_Statements (Item.Body_Stmts);
                     when CM.Stmt_Select =>
                        for Arm of Item.Arms loop
                           case Arm.Kind is
                              when CM.Select_Arm_Channel =>
                                 if Lookup_In_Statements (Arm.Channel_Data.Statements) then
                                    return True;
                                 end if;
                              when CM.Select_Arm_Delay =>
                                 if Lookup_In_Statements (Arm.Delay_Data.Statements) then
                                    return True;
                                 end if;
                              when others =>
                                 null;
                           end case;
                        end loop;
                        return False;
                     when others =>
                        return False;
                  end case;
               end if;
            end if;
         end loop;
         return False;
      end Lookup_In_Statements;
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Subprogram of Unit.Subprograms loop
         if Span_Contains (Subprogram.Span, Span) then
            return
              Lookup_In_Decls (Subprogram.Declarations)
              or else Lookup_In_Statements (Subprogram.Statements);
         end if;
      end loop;

      for Task_Item of Unit.Tasks loop
         if Span_Contains (Task_Item.Span, Span) then
            return
              Lookup_In_Decls (Task_Item.Declarations)
              or else Lookup_In_Statements (Task_Item.Statements);
         end if;
      end loop;

      return Lookup_In_Statements (Unit.Statements);
   end Lookup_Local_Object_Type;

   function Lookup_Selected_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : GM.Type_Descriptor;
      Selector  : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Base : GM.Type_Descriptor := Base_Type (Unit, Document, Prefix);
   begin
      if Selector'Length = 0 or else not Has_Text (Base.Name) then
         return False;
      end if;

      if FT.Lowercase (Selector) = "all"
        and then Is_Access_Type (Base)
        and then Base.Has_Target
      then
         return Type_Info_From_Name (Unit, Document, FT.To_String (Base.Target), Type_Info);
      end if;

      if Is_Access_Type (Base) and then Base.Has_Target then
         Base := Lookup_Type (Unit, Document, FT.To_String (Base.Target));
      end if;

      if Is_Result_Builtin (Base) and then FT.Lowercase (Selector) = "message" then
         Type_Info := BT.String_Type;
         return True;
      end if;

      if Is_Tuple_Type (Base)
        and then Selector (Selector'First) in '0' .. '9'
      then
         declare
            Tuple_Index : constant Positive := Positive (Natural'Value (Selector));
         begin
            if Tuple_Index in Base.Tuple_Element_Types.First_Index .. Base.Tuple_Element_Types.Last_Index then
               return
                 Type_Info_From_Name
                   (Unit,
                    Document,
                    FT.To_String (Base.Tuple_Element_Types (Tuple_Index)),
                    Type_Info);
            end if;
         exception
            when Constraint_Error =>
               return False;
         end;
      end if;

      if FT.To_String (Base.Kind) = "record" then
         if Base.Has_Discriminant
           and then FT.To_String (Base.Discriminant_Name) = Selector
         then
            return
              Type_Info_From_Name
                (Unit,
                 Document,
                 FT.To_String (Base.Discriminant_Type),
                 Type_Info);
         end if;

         for Field of Base.Fields loop
            if FT.To_String (Field.Name) = Selector then
               return
                 Type_Info_From_Name
                   (Unit,
                    Document,
                    FT.To_String (Field.Type_Name),
                    Type_Info);
            end if;
         end loop;
      end if;

      return False;
   end Lookup_Selected_Type;

   function Resolve_Print_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      State     : Emit_State;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Prefix_Info : GM.Type_Descriptor;
      Left_Info   : GM.Type_Descriptor;
      Operator    : constant String :=
        (if Expr /= null and then Has_Text (Expr.Operator) then FT.To_String (Expr.Operator) else "");
   begin
      if Expr = null then
         return False;
      elsif Has_Text (Expr.Type_Name)
        and then Type_Info_From_Name (Unit, Document, FT.To_String (Expr.Type_Name), Type_Info)
      then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_String =>
            Type_Info := BT.String_Type;
            return True;
         when CM.Expr_Bool =>
            Type_Info := BT.Boolean_Type;
            return True;
         when CM.Expr_Int =>
            Type_Info := BT.Integer_Type;
            return True;
         when CM.Expr_Ident =>
            return
              Lookup_Bound_Type (State, FT.To_String (Expr.Name), Type_Info)
              or else Lookup_Object_Type (Unit, FT.To_String (Expr.Name), Type_Info)
              or else
                Lookup_Mir_Local_Type
                  (Document,
                   FT.To_String (Expr.Name),
                   Expr.Span,
                   Type_Info)
              or else
                Lookup_Local_Object_Type
                  (Unit,
                   FT.To_String (Expr.Name),
                   Expr.Span,
                   Type_Info);
         when CM.Expr_Select =>
            return
              Expr.Prefix /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Prefix, State, Prefix_Info)
              and then Lookup_Selected_Type
                (Unit,
                 Document,
                 Prefix_Info,
                 FT.To_String (Expr.Selector),
                 Type_Info);
         when CM.Expr_Resolved_Index =>
            if Expr.Prefix /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Prefix, State, Prefix_Info)
            then
               declare
                  Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Prefix_Info);
               begin
                  if Base.Has_Component_Type then
                     return
                       Type_Info_From_Name
                         (Unit,
                          Document,
                          FT.To_String (Base.Component_Type),
                          Type_Info);
                  end if;
               end;
            end if;
            return False;
         when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Subtype_Indication =>
            return
              (Expr.Target /= null
               and then Resolve_Print_Type (Unit, Document, Expr.Target, State, Type_Info))
              or else
              (Expr.Inner /= null
               and then Resolve_Print_Type (Unit, Document, Expr.Inner, State, Type_Info));
         when CM.Expr_Call =>
            if Expr.Callee /= null
              and then Expr.Callee.Kind in CM.Expr_Ident | CM.Expr_Select
            then
               declare
                  Callee_Name : constant String := FT.To_String (Expr.Callee.Name);
               begin
                  if Callee_Name'Length > 0 then
                     for Subprogram of Unit.Subprograms loop
                        if FT.To_String (Subprogram.Name) = Callee_Name
                          and then Subprogram.Has_Return_Type
                        then
                           Type_Info := Subprogram.Return_Type;
                           return True;
                        end if;
                     end loop;
                  end if;
               end;
            end if;
            return False;
         when CM.Expr_Unary =>
            return
              Expr.Inner /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Inner, State, Type_Info);
         when CM.Expr_Binary =>
            if Operator in "=" | "/=" | "<" | "<=" | ">" | ">=" | "and then" | "or else" then
               Type_Info := BT.Boolean_Type;
               return True;
            elsif Operator in "and" | "or" | "xor" then
               if Expr.Left /= null
                 and then Resolve_Print_Type (Unit, Document, Expr.Left, State, Left_Info)
               then
                  if Is_Binary_Type (Unit, Document, Left_Info) then
                     Type_Info := Left_Info;
                     return True;
                  elsif FT.Lowercase (FT.To_String (Base_Type (Unit, Document, Left_Info).Kind)) = "boolean"
                    or else FT.Lowercase (FT.To_String (Base_Type (Unit, Document, Left_Info).Name)) = "boolean"
                  then
                     Type_Info := BT.Boolean_Type;
                     return True;
                  end if;
               end if;
               return False;
            end if;
            return
              Expr.Left /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Left, State, Type_Info);
         when others =>
            return False;
      end case;
   end Resolve_Print_Type;

   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base            : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind            : constant String := FT.To_String (Base.Kind);
      Name            : constant String := FT.To_String (Base.Name);
      Unresolved_Base : constant String :=
        (if Kind = "subtype" and then Base.Has_Base then FT.To_String (Base.Base) else "");
   begin
      return Kind = "integer"
        or else Is_Builtin_Integer_Name (Name)
        or else Is_Builtin_Integer_Name (Unresolved_Base);
   end Is_Integer_Type;

   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base            : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind            : constant String := FT.To_String (Base.Kind);
      Name            : constant String := FT.To_String (Base.Name);
      Unresolved_Base : constant String :=
        (if Kind = "subtype" and then Base.Has_Base then FT.To_String (Base.Base) else "");
   begin
      return (Kind = "binary" and then Base.Has_Bit_Width)
        or else Is_Builtin_Binary_Name (Name)
        or else Is_Builtin_Binary_Name (Unresolved_Base);
   end Is_Binary_Type;

   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Positive
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Width : constant Natural := Binary_Width_From_Name (FT.To_String (Base.Name));
   begin
      if Base.Has_Bit_Width then
         return Base.Bit_Width;
      elsif Width /= 0 then
         return Positive (Width);
      end if;
      Raise_Internal ("binary type missing bit width during Ada emission");
   end Binary_Bit_Width;

   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base            : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind            : constant String := FT.To_String (Base.Kind);
      Name            : constant String := FT.To_String (Base.Name);
      Unresolved_Base : constant String :=
        (if Kind = "subtype" and then Base.Has_Base then FT.To_String (Base.Base) else "");
   begin
      return Kind = "float"
        or else Is_Builtin_Float_Name (Name)
        or else Is_Builtin_Float_Name (Unresolved_Base);
   end Is_Float_Type;

   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean
   is
   begin
      if Is_Builtin_Integer_Name (Name) then
         return True;
      elsif Has_Type (Unit, Document, Name) then
         return Is_Integer_Type (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      return False;
   end Is_Integer_Type;

   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean
   is
   begin
      if Is_Builtin_Binary_Name (Name) then
         return True;
      elsif Has_Type (Unit, Document, Name) then
         return Is_Binary_Type (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      return False;
   end Is_Binary_Type;

   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Positive
   is
   begin
      if Is_Builtin_Binary_Name (Name) then
         return Positive (Binary_Width_From_Name (Name));
      elsif Has_Type (Unit, Document, Name) then
         return Binary_Bit_Width (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      Raise_Internal ("binary type name missing width during Ada emission");
   end Binary_Bit_Width;

   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean
   is
   begin
      if Is_Builtin_Float_Name (Name) then
         return True;
      elsif Has_Type (Unit, Document, Name) then
         return Is_Float_Type (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      return False;
   end Is_Float_Type;

   function Is_Array_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "array";
   end Is_Array_Type;

   function Is_Tuple_Type (Info : GM.Type_Descriptor) return Boolean is
   begin
      return FT.Lowercase (FT.To_String (Info.Kind)) = "tuple";
   end Is_Tuple_Type;

   function Is_Result_Builtin (Info : GM.Type_Descriptor) return Boolean is
   begin
      return Info.Is_Result_Builtin;
   end Is_Result_Builtin;

   function Render_Result_Empty_Aggregate return String is
   begin
      return
        "(Ok => True, Message => Ada.Strings.Unbounded.Null_Unbounded_String)";
   end Render_Result_Empty_Aggregate;

   function Render_Result_Fail_Aggregate (Message_Image : String) return String is
   begin
      return
        "(Ok => False, Message => Ada.Strings.Unbounded.To_Unbounded_String ("
        & Message_Image
        & "))";
   end Render_Result_Fail_Aggregate;

   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean is
   begin
      return FT.To_String (Info.Kind) = "access";
   end Is_Access_Type;

   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean is
   begin
      return Is_Access_Type (Info)
        and then FT.To_String (Info.Access_Role) = "Owner";
   end Is_Owner_Access;

   function Is_Alias_Access (Info : GM.Type_Descriptor) return Boolean is
      Role : constant String := FT.To_String (Info.Access_Role);
   begin
      return Is_Access_Type (Info)
        and then not Is_Owner_Access (Info)
        and then Role in "Borrow" | "Observe";
   end Is_Alias_Access;

   function Needs_Implicit_Dereference
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean
   is
      Prefix_Info : GM.Type_Descriptor := (others => <>);
   begin
      return Expr /= null
        and then Has_Text (Expr.Type_Name)
        and then Type_Info_From_Name
          (Unit,
           Document,
           FT.To_String (Expr.Type_Name),
           Prefix_Info)
        and then Is_Access_Type (Base_Type (Unit, Document, Prefix_Info));
   end Needs_Implicit_Dereference;

   function Is_String_Type_Name (Name : String) return Boolean is
   begin
      return FT.Lowercase (Name) = "string";
   end Is_String_Type_Name;

   function Is_Bounded_String_Type (Info : GM.Type_Descriptor) return Boolean is
   begin
      return FT.Lowercase (FT.To_String (Info.Kind)) = "string"
        and then Info.Has_Length_Bound;
   end Is_Bounded_String_Type;

   function Bounded_String_Instance_Name (Bound : Natural) return String is
      Image : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (Bound), Ada.Strings.Both);
   begin
      return "Safe_Bounded_String_" & Image;
   end Bounded_String_Instance_Name;

   function Bounded_String_Instance_Name (Info : GM.Type_Descriptor) return String is
   begin
      if not Is_Bounded_String_Type (Info) then
         Raise_Internal ("bounded-string instance requested for non-bounded type");
      end if;
      return Bounded_String_Instance_Name (Info.Length_Bound);
   end Bounded_String_Instance_Name;

   function Bounded_String_Type_Name (Bound : Natural) return String is
      Image : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (Bound), Ada.Strings.Both);
   begin
      return "Safe_Bounded_String_" & Image & "_Type";
   end Bounded_String_Type_Name;

   function Bounded_String_Type_Name (Info : GM.Type_Descriptor) return String is
   begin
      if not Is_Bounded_String_Type (Info) then
         Raise_Internal ("bounded-string type requested for non-bounded type");
      end if;
      return Bounded_String_Type_Name (Info.Length_Bound);
   end Bounded_String_Type_Name;

   function Synthetic_Bounded_String_Type
     (Name  : String;
      Found : out Boolean) return GM.Type_Descriptor
   is
      Prefix : constant String := "__bounded_string_";
   begin
      Found := False;
      if not Starts_With (Name, Prefix) then
         return (others => <>);
      end if;

      declare
         Bound_Text : constant String :=
           Name (Name'First + Prefix'Length .. Name'Last);
      begin
         if Bound_Text'Length = 0 then
            return (others => <>);
         end if;
         for Ch of Bound_Text loop
            if Ch not in '0' .. '9' then
               return (others => <>);
            end if;
         end loop;
         Found := True;
         declare
            Result : GM.Type_Descriptor := (others => <>);
            Bound  : constant Natural := Natural'Value (Bound_Text);
         begin
            Result.Name := FT.To_UString (Name);
            Result.Kind := FT.To_UString ("string");
            Result.Has_Base := True;
            Result.Base := FT.To_UString ("string");
            Result.Has_Length_Bound := True;
            Result.Length_Bound := Bound;
            return Result;
         end;
      exception
         when Constraint_Error =>
            Found := False;
            return (others => <>);
      end;
   end Synthetic_Bounded_String_Type;

   procedure Register_Bounded_String_Type
     (State : in out Emit_State;
      Info  : GM.Type_Descriptor) is
      Bound_Text : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (Info.Length_Bound), Ada.Strings.Both);
   begin
      if not Is_Bounded_String_Type (Info) then
         return;
      end if;
      State.Needs_Safe_Bounded_Strings := True;
      if not Contains_Name (State.Bounded_String_Bounds, Bound_Text) then
         State.Bounded_String_Bounds.Append (FT.To_UString (Bound_Text));
      end if;
   end Register_Bounded_String_Type;

   function Is_Plain_String_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "string"
        and then not Base.Has_Length_Bound;
   end Is_Plain_String_Type;

   function Is_Growable_Array_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Growable;
   end Is_Growable_Array_Type;

   function Sanitized_Helper_Name (Name : String) return String is
      Result : SU.Unbounded_String;
   begin
      for Ch of Name loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Result := Result & SU.To_Unbounded_String ((1 => Ch));
         else
            Result := Result & SU.To_Unbounded_String ("_");
         end if;
      end loop;
      return SU.To_String (Result);
   end Sanitized_Helper_Name;

   function Local_Clone_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Clone_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Clone_Helper_Name;

   function Local_Free_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Free_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Free_Helper_Name;

   function Local_Allocate_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Allocate_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Allocate_Helper_Name;

   function Local_Dispose_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Dispose_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Dispose_Helper_Name;

   function Array_Runtime_Instance_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Safe_Name (FT.To_String (Info.Name)) & "_RT";
   end Array_Runtime_Instance_Name;

   function Array_Runtime_Default_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Safe_Name (FT.To_String (Info.Name)) & "_Default_Element";
   end Array_Runtime_Default_Element_Name;

   function Array_Runtime_Clone_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Safe_Name (FT.To_String (Info.Name)) & "_Clone_Element";
   end Array_Runtime_Clone_Element_Name;

   function Array_Runtime_Free_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Safe_Name (FT.To_String (Info.Name)) & "_Free_Element";
   end Array_Runtime_Free_Element_Name;

   function Resolve_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return GM.Type_Descriptor
   is
      Found_Synthetic : Boolean := False;
      Synthetic       : GM.Type_Descriptor := (others => <>);
      Lower_Name      : constant String := FT.Lowercase (Name);
      Result          : GM.Type_Descriptor := (others => <>);
      Not_Null_Access_Constant_Prefix : constant String := "not null access constant ";
      Access_Constant_Prefix          : constant String := "access constant ";
      Not_Null_Access_Prefix          : constant String := "not null access ";
      Access_Prefix                   : constant String := "access ";
   begin
      if Name'Length = 0 then
         return (others => <>);
      end if;

      if Has_Type (Unit, Document, Name) then
         return Lookup_Type (Unit, Document, Name);
      elsif Starts_With (Lower_Name, "not null access constant ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString
             (Name (Name'First + Not_Null_Access_Constant_Prefix'Length .. Name'Last));
         Result.Not_Null := True;
         Result.Is_Constant := True;
         return Result;
      elsif Starts_With (Lower_Name, "access constant ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString (Name (Name'First + Access_Constant_Prefix'Length .. Name'Last));
         Result.Is_Constant := True;
         return Result;
      elsif Starts_With (Lower_Name, "not null access ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString (Name (Name'First + Not_Null_Access_Prefix'Length .. Name'Last));
         Result.Not_Null := True;
         return Result;
      elsif Starts_With (Lower_Name, "access ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target := FT.To_UString (Name (Name'First + Access_Prefix'Length .. Name'Last));
         return Result;
      elsif Lower_Name = "safe_string_rt.safe_string" then
         return BT.String_Type;
      elsif Starts_With (Lower_Name, "safe_tuple_") then
         return
           (Name => FT.To_UString (Name),
            Kind => FT.To_UString ("tuple"),
            others => <>);
      elsif Starts_With (Name, "__growable_array_") then
         declare
            Prefix : constant String := "__growable_array_";
            Suffix : constant String := Name (Name'First + Prefix'Length .. Name'Last);
         begin
            Result.Name := FT.To_UString (Name);
            Result.Kind := FT.To_UString ("array");
            Result.Growable := True;
            Result.Has_Component_Type := True;
            Result.Component_Type :=
              Resolve_Type_Name (Unit, Document, Suffix).Name;
            return Result;
         end;
      elsif Starts_With (Lower_Name, "safe_constraint_")
        or else Starts_With (Name, "__constraint_")
      then
         Result.Name := FT.To_UString (Name);
         Result.Kind := FT.To_UString ("subtype");
         if Ada.Strings.Fixed.Index (Lower_Name, "integer") > 0 then
            Result.Has_Base := True;
            Result.Base := FT.To_UString ("integer");
         elsif Ada.Strings.Fixed.Index (Lower_Name, "string") > 0 then
            Result.Has_Base := True;
            Result.Base := FT.To_UString ("string");
         end if;
         return Result;
      elsif Lower_Name = "string" then
         return BT.String_Type;
      elsif Lower_Name = "boolean" then
         return BT.Boolean_Type;
      elsif Is_Builtin_Integer_Name (Lower_Name) then
         return BT.Integer_Type;
      elsif Is_Builtin_Float_Name (Lower_Name) then
         return
           (if Lower_Name = "long_float"
            then BT.Long_Float_Type
            elsif Lower_Name = "duration"
            then BT.Duration_Type
            else BT.Float_Type);
      elsif Is_Builtin_Binary_Name (Lower_Name) then
         return BT.Binary_Type (Positive (Binary_Width_From_Name (Lower_Name)));
      elsif Lower_Name = "result" then
         return BT.Result_Type;
      end if;

      Synthetic := Synthetic_Bounded_String_Type (Name, Found_Synthetic);
      if Found_Synthetic then
         return Synthetic;
      end if;

      Raise_Internal ("type lookup failed during Ada emission for '" & Name & "'");
   end Resolve_Type_Name;

   function Has_Heap_Value_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      if Is_Plain_String_Type (Unit, Document, Base)
        or else Is_Growable_Array_Type (Unit, Document, Base)
      then
         return True;
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Has_Component_Type
      then
         return
           Has_Heap_Value_Type
             (Unit,
              Document,
              Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type)));
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "record" then
         for Field of Base.Fields loop
            if Has_Heap_Value_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name)))
            then
               return True;
            end if;
         end loop;
         for Field of Base.Variant_Fields loop
            if Has_Heap_Value_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name)))
            then
               return True;
            end if;
         end loop;
      elsif Is_Tuple_Type (Base) then
         for Item of Base.Tuple_Element_Types loop
            if Has_Heap_Value_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Item)))
            then
               return True;
            end if;
         end loop;
      end if;

      return False;
   end Has_Heap_Value_Type;

   function Tuple_Field_Name (Index : Positive) return String is
   begin
      return "F" & Ada.Strings.Fixed.Trim (Positive'Image (Index), Ada.Strings.Both);
   end Tuple_Field_Name;

   function Tuple_String_Discriminant_Name (Index : Positive) return String is
   begin
      return Tuple_Field_Name (Index) & "_Length";
   end Tuple_String_Discriminant_Name;

   function Expr_Type_Info
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return GM.Type_Descriptor
   is
      Found_Synthetic : Boolean := False;
   begin
      if Expr = null or else not Has_Text (Expr.Type_Name) then
         return (others => <>);
      elsif Has_Type (Unit, Document, FT.To_String (Expr.Type_Name)) then
         return Lookup_Type (Unit, Document, FT.To_String (Expr.Type_Name));
      elsif FT.Lowercase (FT.To_String (Expr.Type_Name)) = "string" then
         return BT.String_Type;
      elsif FT.Lowercase (FT.To_String (Expr.Type_Name)) = "boolean" then
         return BT.Boolean_Type;
      elsif FT.Lowercase (FT.To_String (Expr.Type_Name)) = "integer" then
         return BT.Integer_Type;
      else
         return Synthetic_Bounded_String_Type (FT.To_String (Expr.Type_Name), Found_Synthetic);
      end if;
   end Expr_Type_Info;

   function Try_Static_Integer_Value
     (Expr  : CM.Expr_Access;
      Value : out Long_Long_Integer) return Boolean
   is
      Inner_Value : Long_Long_Integer := 0;
   begin
      Value := 0;
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Int =>
            Value := Long_Long_Integer (Expr.Int_Value);
            return True;
         when CM.Expr_Unary =>
            if Expr.Inner = null
              or else not Try_Static_Integer_Value (Expr.Inner, Inner_Value)
            then
               return False;
            elsif FT.To_String (Expr.Operator) = "-" then
               Value := -Inner_Value;
               return True;
            elsif FT.To_String (Expr.Operator) = "+" then
               Value := Inner_Value;
               return True;
            end if;
         when others =>
            null;
      end case;

      return False;
   end Try_Static_Integer_Value;

   function Fixed_Array_Cardinality
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Info : GM.Type_Descriptor;
      Cardinality : out Natural) return Boolean
   is
      Base       : constant GM.Type_Descriptor := Base_Type (Unit, Document, Target_Info);
      Index_Info : GM.Type_Descriptor := (others => <>);
      Width      : Long_Long_Integer := 0;
   begin
      Cardinality := 0;
      if FT.Lowercase (FT.To_String (Base.Kind)) /= "array"
        or else Base.Growable
        or else Natural (Base.Index_Types.Length) /= 1
      then
         return False;
      end if;

      Index_Info :=
        Resolve_Type_Name
          (Unit,
           Document,
           FT.To_String (Base.Index_Types (Base.Index_Types.First_Index)));
      if not Index_Info.Has_Low or else not Index_Info.Has_High then
         Index_Info := Base_Type (Unit, Document, Index_Info);
         if not Index_Info.Has_Low or else not Index_Info.Has_High then
            return False;
         end if;
      end if;

      Width := Index_Info.High - Index_Info.Low + 1;
      if Width < 0 or else Width > Long_Long_Integer (Natural'Last) then
         return False;
      end if;

      Cardinality := Natural (Width);
      return True;
   end Fixed_Array_Cardinality;

   function Static_Growable_Length
     (Expr   : CM.Expr_Access;
      Length : out Natural) return Boolean
   is
      Low_Value  : Long_Long_Integer := 0;
      High_Value : Long_Long_Integer := 0;
      Width      : Long_Long_Integer := 0;
   begin
      Length := 0;
      if Expr = null then
         return False;
      elsif Expr.Kind = CM.Expr_Array_Literal then
         Length := Natural (Expr.Elements.Length);
         return True;
      elsif Expr.Kind = CM.Expr_Resolved_Index
        and then Expr.Prefix /= null
        and then Expr.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select
        and then Natural (Expr.Args.Length) = 2
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index),
           Low_Value)
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index + 1),
           High_Value)
      then
         if High_Value < Low_Value then
            return False;
         end if;
         Width := High_Value - Low_Value + 1;
         if Width < 0 or else Width > Long_Long_Integer (Natural'Last) then
            return False;
         end if;
         Length := Natural (Width);
         return True;
      end if;

      return False;
   end Static_Growable_Length;

   function Render_Fixed_Array_As_Growable
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String
   is
      Runtime_Name : constant String := Array_Runtime_Instance_Name (Target_Info);
      Literal_Image : SU.Unbounded_String;
      Component_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Name (Unit, Document, FT.To_String (Target_Info.Component_Type));
   begin
      State.Needs_Safe_Array_RT := True;

      if Expr /= null and then Expr.Kind in CM.Expr_Array_Literal | CM.Expr_Tuple then
         Literal_Image := SU.To_Unbounded_String ("(");
         for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
            if Index /= Expr.Elements.First_Index then
               Literal_Image := Literal_Image & SU.To_Unbounded_String (", ");
            end if;
            Literal_Image :=
              Literal_Image
              & SU.To_Unbounded_String
                  (Render_Expr_For_Target_Type
                     (Unit,
                      Document,
                      Expr.Elements (Index),
                      Component_Info,
                      State));
         end loop;
         Literal_Image := Literal_Image & SU.To_Unbounded_String (")");
         return
           Runtime_Name
           & ".From_Array ("
           & Runtime_Name
           & ".Element_Array'"
           & SU.To_String (Literal_Image)
           & ")";
      end if;

      return
        Runtime_Name
        & ".From_Array ("
        & Runtime_Name
        & ".Element_Array ("
        & Render_Expr (Unit, Document, Expr, State)
        & "))";
   end Render_Fixed_Array_As_Growable;

   function Render_Growable_As_Fixed
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String
   is
      Cardinality    : Natural := 0;
      Element_Count  : Natural := 0;
      Component_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Name (Unit, Document, FT.To_String (Target_Info.Component_Type));
      Slice_Source_Info : GM.Type_Descriptor := (others => <>);
      Result         : SU.Unbounded_String := SU.To_Unbounded_String ("(");
      Low_Value      : Long_Long_Integer := 0;
      High_Value     : Long_Long_Integer := 0;
   begin
      if not Fixed_Array_Cardinality (Unit, Document, Target_Info, Cardinality) then
         Raise_Unsupported
           (State,
            (if Expr = null then FT.Null_Span else Expr.Span),
            "growable-to-fixed conversion requires a statically exact array length");
      end if;

      if Expr.Kind = CM.Expr_Array_Literal then
         if not Static_Growable_Length (Expr, Element_Count)
           or else Cardinality /= Element_Count
         then
            Raise_Unsupported
              (State,
               Expr.Span,
               "growable-to-fixed conversion requires a statically exact array length");
         end if;

         for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
            if Index /= Expr.Elements.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Render_Expr_For_Target_Type
                     (Unit,
                      Document,
                      Expr.Elements (Index),
                      Component_Info,
                      State));
         end loop;
      elsif Expr.Kind in CM.Expr_Ident | CM.Expr_Select then
         Slice_Source_Info :=
           Base_Type
             (Unit,
              Document,
              Expr_Type_Info (Unit, Document, Expr));
         if not Is_Growable_Array_Type (Unit, Document, Slice_Source_Info) then
            declare
               Resolved_Source_Info : GM.Type_Descriptor := (others => <>);
            begin
               if Expr.Kind = CM.Expr_Ident
                 and then Lookup_Mir_Local_Type
                   (Document,
                    FT.To_String (Expr.Name),
                    Expr.Span,
                    Resolved_Source_Info)
               then
                  Slice_Source_Info :=
                    Base_Type (Unit, Document, Resolved_Source_Info);
               elsif Resolve_Print_Type (Unit, Document, Expr, State, Resolved_Source_Info) then
                  Slice_Source_Info :=
                    Base_Type (Unit, Document, Resolved_Source_Info);
               else
                  return Render_Expr (Unit, Document, Expr, State);
               end if;
            end;
         end if;
         if not Is_Growable_Array_Type (Unit, Document, Slice_Source_Info) then
            return Render_Expr (Unit, Document, Expr, State);
         end if;

         for Offset in 0 .. Cardinality - 1 loop
            declare
               Index_Expr  : constant CM.Expr_Access :=
                 new CM.Expr_Node'
                   (Kind      => CM.Expr_Int,
                    Span      => Expr.Span,
                    Type_Name => FT.To_UString ("integer"),
                    Int_Value => CM.Wide_Integer (Offset + 1),
                    others    => <>);
            begin
               if Offset /= 0 then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Array_Runtime_Instance_Name (Slice_Source_Info)
                      & ".Element ("
                      & Render_Expr (Unit, Document, Expr, State)
                      & ", "
                      & Render_Expr (Unit, Document, Index_Expr, State)
                      & ")");
            end;
         end loop;
      elsif Expr.Kind = CM.Expr_Resolved_Index
        and then Expr.Prefix /= null
        and then Expr.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select
        and then Natural (Expr.Args.Length) = 2
        and then Static_Growable_Length (Expr, Element_Count)
        and then Cardinality = Element_Count
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index),
           Low_Value)
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index + 1),
           High_Value)
      then
         Slice_Source_Info :=
           Base_Type
             (Unit,
              Document,
              Expr_Type_Info (Unit, Document, Expr.Prefix));
         if not Is_Growable_Array_Type (Unit, Document, Slice_Source_Info) then
            Raise_Unsupported
              (State,
               Expr.Span,
               "static slice conversion requires a growable-array source");
         end if;

         for Offset in 0 .. Cardinality - 1 loop
            declare
               Index_Value : constant Long_Long_Integer := Low_Value + Long_Long_Integer (Offset);
               Index_Expr  : constant CM.Expr_Access :=
                 new CM.Expr_Node'
                   (Kind      => CM.Expr_Int,
                    Span      => Expr.Span,
                    Type_Name => FT.To_UString ("integer"),
                    Int_Value => CM.Wide_Integer (Index_Value),
                    others    => <>);
            begin
               if Offset /= 0 then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Array_Runtime_Instance_Name (Slice_Source_Info)
                      & ".Element ("
                      & Render_Expr (Unit, Document, Expr.Prefix, State)
                      & ", "
                      & Render_Expr (Unit, Document, Index_Expr, State)
                      & ")");
            end;
         end loop;
      else
         Raise_Unsupported
           (State,
            Expr.Span,
            "growable-to-fixed conversion is only supported for bracket literals, guarded object names, and static slices");
      end if;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Growable_As_Fixed;

   function Render_Growable_Array_Expr
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String
   is
      Array_Info : GM.Type_Descriptor := Base_Type (Unit, Document, Target_Info);
      Source_Info : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Expr));
      Result     : SU.Unbounded_String;
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null growable-array expression during Ada emission");
      end if;

      if not Is_Growable_Array_Type (Unit, Document, Array_Info) then
         Array_Info := Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Expr));
      end if;

      if not Is_Growable_Array_Type (Unit, Document, Array_Info) then
         Raise_Unsupported
           (State,
            Expr.Span,
            "encountered non-growable-array expression in growable-array emission");
      end if;

      State.Needs_Safe_Array_RT := True;

      if Expr.Kind = CM.Expr_Array_Literal then
         if Expr.Elements.Is_Empty then
            return Array_Runtime_Instance_Name (Array_Info) & ".Empty";
         end if;

         Result := SU.To_Unbounded_String ("(");
         for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
            if Index /= Expr.Elements.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            if Expr.Elements.Length = 1 then
               Result := Result & SU.To_Unbounded_String ("1 => ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Render_Expr_For_Target_Type
                     (Unit,
                      Document,
                      Expr.Elements (Index),
                      Resolve_Type_Name
                        (Unit,
                         Document,
                         FT.To_String (Array_Info.Component_Type)),
                      State));
         end loop;
         Result := Result & SU.To_Unbounded_String (")");
         return
           Array_Runtime_Instance_Name (Array_Info)
           & ".From_Array ("
           & SU.To_String (Result)
           & ")";
      elsif Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
         declare
            Prefix_Info : constant GM.Type_Descriptor :=
              Expr_Type_Info (Unit, Document, Expr.Prefix);
         begin
            if Is_Growable_Array_Type (Unit, Document, Prefix_Info) then
               if Natural (Expr.Args.Length) = 1 then
                  return
                    Array_Runtime_Instance_Name (Array_Info)
                    & ".Element ("
                    & Render_Expr (Unit, Document, Expr.Prefix, State)
                    & ", "
                    & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State)
                    & ")";
               elsif Natural (Expr.Args.Length) = 2 then
                  return
                    Array_Runtime_Instance_Name (Array_Info)
                    & ".Slice ("
                    & Render_Expr (Unit, Document, Expr.Prefix, State)
                    & ", "
                    & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State)
                    & ", "
                    & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State)
                    & ")";
               end if;
            end if;
         end;
      elsif Expr.Kind = CM.Expr_Binary
        and then FT.To_String (Expr.Operator) = "&"
      then
         return
           Array_Runtime_Instance_Name (Array_Info)
           & ".Concat ("
           & Render_Growable_Array_Expr
               (Unit, Document, Expr.Left, Array_Info, State)
           & ", "
           & Render_Growable_Array_Expr
               (Unit, Document, Expr.Right, Array_Info, State)
           & ")";
      elsif FT.Lowercase (FT.To_String (Source_Info.Kind)) = "array"
        and then not Source_Info.Growable
      then
         return
           Render_Fixed_Array_As_Growable
             (Unit, Document, Expr, Array_Info, State);
      end if;

      return Render_Expr (Unit, Document, Expr, State);
   end Render_Growable_Array_Expr;

   function Render_Heap_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Info : constant GM.Type_Descriptor := Expr_Type_Info (Unit, Document, Expr);
   begin
      State.Needs_Safe_String_RT := True;

      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null heap-string expression during Ada emission");
      elsif Expr.Kind = CM.Expr_String and then Has_Text (Expr.Text) then
         return "Safe_String_RT.From_Literal (" & FT.To_String (Expr.Text) & ")";
      elsif Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
         declare
            Prefix_Info : constant GM.Type_Descriptor := Expr_Type_Info (Unit, Document, Expr.Prefix);
            Low_Image   : constant String :=
              Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State);
         begin
            if Is_Plain_String_Type (Unit, Document, Prefix_Info) then
               if Natural (Expr.Args.Length) = 1 then
                  return
                    "Safe_String_RT.Slice ("
                    & Render_Heap_String_Expr (Unit, Document, Expr.Prefix, State)
                    & ", "
                    & Low_Image
                    & ", "
                    & Low_Image
                    & ")";
               end if;
               return
                 "Safe_String_RT.Slice ("
                 & Render_Heap_String_Expr (Unit, Document, Expr.Prefix, State)
                 & ", "
                 & Low_Image
                  & ", "
                  & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State)
                  & ")";
            elsif Is_Bounded_String_Type (Prefix_Info) then
               Register_Bounded_String_Type (State, Prefix_Info);
               if Natural (Expr.Args.Length) = 1 then
                  return
                    "Safe_String_RT.From_Literal ("
                    & Bounded_String_Instance_Name (Prefix_Info)
                    & ".To_String ("
                    & Render_Expr (Unit, Document, Expr.Prefix, State)
                    & ") ("
                    & Low_Image
                    & " .. "
                    & Low_Image
                    & "))";
               end if;
               return
                 "Safe_String_RT.From_Literal ("
                 & Bounded_String_Instance_Name (Prefix_Info)
                 & ".To_String ("
                 & Render_Expr (Unit, Document, Expr.Prefix, State)
                 & ") ("
                 & Low_Image
                 & " .. "
                 & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State)
                 & "))";
            end if;
         end;
      elsif Expr.Kind = CM.Expr_Binary
        and then FT.To_String (Expr.Operator) = "&"
      then
         return
           "Safe_String_RT.Concat ("
           & Render_Heap_String_Expr (Unit, Document, Expr.Left, State)
           & ", "
           & Render_Heap_String_Expr (Unit, Document, Expr.Right, State)
           & ")";
      end if;

      if Is_Plain_String_Type (Unit, Document, Info) then
         return Render_Expr (Unit, Document, Expr, State);
      elsif Is_Bounded_String_Type (Info) then
         return
           "Safe_String_RT.From_Literal ("
           & Render_String_Expr (Unit, Document, Expr, State)
           & ")";
      end if;

      return
        "Safe_String_RT.From_Literal ("
        & Render_String_Expr (Unit, Document, Expr, State)
        & ")";
   end Render_Heap_String_Expr;

   function Render_Positional_Tuple_Aggregate
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Result         : SU.Unbounded_String := SU.To_Unbounded_String ("(");
      Aggregate_Info : constant GM.Type_Descriptor :=
        Expr_Type_Info (Unit, Document, Expr);
   begin
      if Expr = null then
         return "()";
      end if;

      for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
         declare
            Target_Info : GM.Type_Descriptor := (others => <>);
            Has_Target  : Boolean := False;
         begin
            if Is_Array_Type (Unit, Document, Aggregate_Info)
              and then Aggregate_Info.Has_Component_Type
            then
               Target_Info :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Aggregate_Info.Component_Type));
               Has_Target := True;
            elsif Is_Tuple_Type (Aggregate_Info)
              and then Index <= Aggregate_Info.Tuple_Element_Types.Last_Index
            then
               Target_Info :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Aggregate_Info.Tuple_Element_Types (Index)));
               Has_Target := True;
            elsif Expr.Elements (Index) /= null
              and then Has_Text (Expr.Elements (Index).Type_Name)
            then
               Target_Info :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Expr.Elements (Index).Type_Name));
               Has_Target := Has_Text (Target_Info.Name);
            end if;

            if Index /= Expr.Elements.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  ((if Has_Target
                    then Render_Expr_For_Target_Type
                      (Unit,
                       Document,
                       Expr.Elements (Index),
                       Target_Info,
                       State)
                    else Render_Expr (Unit, Document, Expr.Elements (Index), State)));
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Positional_Tuple_Aggregate;

   function Render_Scalar_Value (Value : GM.Scalar_Value) return String is
   begin
      case Value.Kind is
         when GM.Scalar_Value_Integer =>
            return Trim_Image (Value.Int_Value);
         when GM.Scalar_Value_Boolean =>
            return (if Value.Bool_Value then "true" else "false");
         when GM.Scalar_Value_Character =>
            return FT.To_String (Value.Text);
         when others =>
            return "";
      end case;
   end Render_Scalar_Value;

   function Render_Record_Aggregate_For_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      Type_Info : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Result : SU.Unbounded_String := SU.To_Unbounded_String ("(");
      First_Association : Boolean := True;
   begin
      if Expr = null then
         return "()";
      end if;

      if not Type_Info.Discriminant_Constraints.Is_Empty then
         for Constraint of Type_Info.Discriminant_Constraints loop
            if not First_Association then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Constraint.Name)
                   & " => "
                   & Render_Scalar_Value (Constraint.Value));
            First_Association := False;
         end loop;
      end if;

      for Field of Expr.Fields loop
         declare
            Field_Type : GM.Type_Descriptor := (others => <>);
         begin
            for Item of Type_Info.Fields loop
               if FT.To_String (Item.Name) = FT.To_String (Field.Field_Name) then
                  Field_Type := Resolve_Type_Name (Unit, Document, FT.To_String (Item.Type_Name));
                  exit;
               end if;
            end loop;
            if not First_Association then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Field.Field_Name)
                   & " => "
                   & (if Has_Text (Field_Type.Name)
                      then Render_Expr_For_Target_Type
                        (Unit, Document, Field.Expr, Field_Type, State)
                      else Render_Expr (Unit, Document, Field.Expr, State)));
            First_Association := False;
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Record_Aggregate_For_Type;

   function Render_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Expr_Type_Info : GM.Type_Descriptor := (others => <>);
      Has_Expr_Type  : Boolean := False;
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null string expression during Ada emission");
      end if;

      if Has_Text (Expr.Type_Name) then
         declare
            Type_Name : constant String := FT.To_String (Expr.Type_Name);
            Found_Synthetic : Boolean := False;
         begin
            if Type_Info_From_Name (Unit, Document, Type_Name, Expr_Type_Info) then
               Has_Expr_Type := True;
            else
               Expr_Type_Info := Synthetic_Bounded_String_Type (Type_Name, Found_Synthetic);
               Has_Expr_Type := Found_Synthetic;
            end if;
         end;
      end if;

      if Expr.Kind = CM.Expr_String and then Has_Text (Expr.Text) then
         return FT.To_String (Expr.Text);
      elsif Has_Expr_Type and then Is_Plain_String_Type (Unit, Document, Expr_Type_Info) then
         State.Needs_Safe_String_RT := True;
         return
           "Safe_String_RT.To_String ("
           & Render_Heap_String_Expr (Unit, Document, Expr, State)
           & ")";
      elsif Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
         declare
            Prefix_Type : GM.Type_Descriptor := (others => <>);
            Prefix_Has_Type : Boolean := False;
            Prefix_Image : constant String := Render_Expr (Unit, Document, Expr.Prefix, State);
            Low_Image    : constant String := Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State);
         begin
            if Has_Text (Expr.Prefix.Type_Name) then
               declare
                  Type_Name : constant String := FT.To_String (Expr.Prefix.Type_Name);
                  Found_Synthetic : Boolean := False;
               begin
                  if Type_Info_From_Name (Unit, Document, Type_Name, Prefix_Type) then
                     Prefix_Has_Type := True;
                  else
                     Prefix_Type := Synthetic_Bounded_String_Type (Type_Name, Found_Synthetic);
                     Prefix_Has_Type := Found_Synthetic;
                  end if;
               end;
            end if;

            if Prefix_Has_Type and then Is_Bounded_String_Type (Prefix_Type) then
               Register_Bounded_String_Type (State, Prefix_Type);
               declare
                  Base_Image : constant String :=
                    Bounded_String_Instance_Name (Prefix_Type)
                    & ".To_String ("
                    & Prefix_Image
                    & ")";
               begin
                  if Natural (Expr.Args.Length) = 1 then
                     return Base_Image & " (" & Low_Image & " .. " & Low_Image & ")";
                  end if;
                  declare
                     High_Image : constant String :=
                       Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State);
                  begin
                     return Base_Image & " (" & Low_Image & " .. " & High_Image & ")";
                  end;
               end;
            end if;
         end;
      elsif Has_Expr_Type and then Is_Bounded_String_Type (Expr_Type_Info) then
         Register_Bounded_String_Type (State, Expr_Type_Info);
         return
           Bounded_String_Instance_Name (Expr_Type_Info)
           & ".To_String ("
           & Render_Expr (Unit, Document, Expr, State)
           & ")";
      end if;

      return Render_Expr (Unit, Document, Expr, State);
   end Render_String_Expr;

   function Render_String_Length_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null string expression during Ada emission");
      elsif Has_Text (Expr.Type_Name) then
         declare
            Expr_Type : GM.Type_Descriptor := (others => <>);
            Has_Expr_Type : Boolean := False;
         begin
            if Type_Info_From_Name
              (Unit, Document, FT.To_String (Expr.Type_Name), Expr_Type)
            then
               Has_Expr_Type := True;
            else
               Expr_Type :=
                 Synthetic_Bounded_String_Type
                   (FT.To_String (Expr.Type_Name), Has_Expr_Type);
            end if;

            if not Has_Expr_Type then
               return "String'(" & Render_String_Expr (Unit, Document, Expr, State) & ")'Length";
            end if;

            if Is_Bounded_String_Type (Expr_Type) then
               Register_Bounded_String_Type (State, Expr_Type);
               return
                 "Long_Long_Integer ("
                 & Bounded_String_Instance_Name (Expr_Type)
                 & ".Length ("
                 & Render_Expr (Unit, Document, Expr, State)
                 & "))";
            elsif Is_Plain_String_Type (Unit, Document, Expr_Type) then
               State.Needs_Safe_String_RT := True;
               return
                 "Long_Long_Integer (Safe_String_RT.Length ("
                 & Render_Heap_String_Expr (Unit, Document, Expr, State)
                 & "))";
            end if;
         end;
      end if;

      return
        "Long_Long_Integer (String'("
        & Render_String_Expr (Unit, Document, Expr, State)
        & ")'Length)";
   end Render_String_Length_Expr;

   function Render_Expr_For_Target_Type
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String
   is
      Source_Type_Info : GM.Type_Descriptor := (others => <>);
      Target_Is_String : constant Boolean :=
        FT.Lowercase (FT.To_String (Target_Info.Kind)) = "string";
      Has_Expr_Type  : Boolean := False;
   begin
      if Expr = null then
         return "";
      end if;

      if Has_Text (Expr.Type_Name) then
         declare
            Found_Synthetic : Boolean := False;
         begin
            if Type_Info_From_Name
              (Unit, Document, FT.To_String (Expr.Type_Name), Source_Type_Info)
            then
               Has_Expr_Type := True;
            else
               Source_Type_Info :=
                 Synthetic_Bounded_String_Type
                   (FT.To_String (Expr.Type_Name), Found_Synthetic);
               Has_Expr_Type := Found_Synthetic;
            end if;
         end;
      end if;

      if not Has_Expr_Type then
         Has_Expr_Type := Resolve_Print_Type (Unit, Document, Expr, State, Source_Type_Info);
      end if;

      if Is_Bounded_String_Type (Target_Info) then
         Register_Bounded_String_Type (State, Target_Info);
         return
           Bounded_String_Instance_Name (Target_Info)
           & ".To_Bounded ("
           & Render_String_Expr (Unit, Document, Expr, State)
           & ")";
      elsif Is_Owner_Access (Target_Info)
        and then Target_Info.Has_Target
        and then Expr.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
      then
         declare
            Access_Target : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Target_Info.Target));
         begin
            return
              Local_Allocate_Helper_Name (Target_Info)
              & " ("
              & Render_Type_Name (Access_Target)
              & "'"
              & (if Expr.Kind = CM.Expr_Aggregate
                 then
                   Render_Record_Aggregate_For_Type
                     (Unit, Document, Expr, Access_Target, State)
                 else Render_Expr (Unit, Document, Expr, State))
              & ")";
         end;
      elsif Is_Plain_String_Type (Unit, Document, Target_Info) then
         State.Needs_Safe_String_RT := True;
         return Render_Heap_String_Expr (Unit, Document, Expr, State);
      elsif Is_Growable_Array_Type (Unit, Document, Target_Info) then
         return Render_Growable_Array_Expr
           (Unit, Document, Expr, Target_Info, State);
      elsif FT.Lowercase (FT.To_String (Base_Type (Unit, Document, Target_Info).Kind)) = "array"
        and then not Base_Type (Unit, Document, Target_Info).Growable
        and then
          (Expr.Kind = CM.Expr_Array_Literal
           or else Expr.Kind in CM.Expr_Ident | CM.Expr_Select
           or else
             (Expr.Kind = CM.Expr_Resolved_Index
              and then Expr.Prefix /= null
              and then Is_Growable_Array_Type
                (Unit,
                 Document,
                 Safe_Frontend.Ada_Emit.Expr_Type_Info
                   (Unit, Document, Expr.Prefix)))
           or else
             (Has_Expr_Type
              and then Is_Growable_Array_Type
                (Unit,
                 Document,
                 Source_Type_Info)))
      then
         return Render_Growable_As_Fixed
           (Unit, Document, Expr, Target_Info, State);
      elsif Target_Is_String
        and then not Is_Bounded_String_Type (Target_Info)
        and then Has_Expr_Type
        and then Is_Bounded_String_Type (Source_Type_Info)
      then
         return Render_String_Expr (Unit, Document, Expr, State);
      end if;

      return Render_Expr (Unit, Document, Expr, State);
   end Render_Expr_For_Target_Type;

   function Render_Type_Name (Info : GM.Type_Descriptor) return String is
      Result : SU.Unbounded_String;
   begin
      if Info.Anonymous and then Is_Access_Type (Info) then
         return
           (if Info.Not_Null then "not null " else "")
           & "access "
           & (if Info.Is_Constant then "constant " else "")
           & Ada_Safe_Name (FT.To_String (Info.Target));
      elsif FT.To_String (Info.Kind) = "subtype"
        and then not Info.Discriminant_Constraints.Is_Empty
        and then not Starts_With (FT.To_String (Info.Name), "__constraint")
      then
         Result :=
           SU.To_Unbounded_String
             (Ada_Safe_Name
                ((if Info.Has_Base then FT.To_String (Info.Base) else FT.To_String (Info.Name)))
              & " (");
         for Index in Info.Discriminant_Constraints.First_Index .. Info.Discriminant_Constraints.Last_Index loop
            declare
               Constraint : constant GM.Discriminant_Constraint :=
                 Info.Discriminant_Constraints (Index);
            begin
               if Index /= Info.Discriminant_Constraints.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               if Constraint.Is_Named then
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (FT.To_String (Constraint.Name) & " => ");
               end if;
               Result :=
                 Result & SU.To_Unbounded_String (Render_Scalar_Value (Constraint.Value));
            end;
         end loop;
         Result := Result & SU.To_Unbounded_String (")");
         return SU.To_String (Result);
      elsif FT.To_String (Info.Kind) = "subtype"
        and then Starts_With (FT.To_String (Info.Name), "__constraint")
        and then Info.Has_Base
        and then Info.Has_Low
        and then Info.Has_High
      then
         return Ada_Safe_Name (FT.To_String (Info.Name));
      elsif FT.Lowercase (FT.To_String (Info.Kind)) = "string"
        and then not Info.Has_Length_Bound
      then
         return "Safe_String_RT.Safe_String";
      elsif FT.Lowercase (FT.To_String (Info.Kind)) = "subtype"
        and then Info.Has_Base
        and then FT.Lowercase (FT.To_String (Info.Base)) = "string"
        and then not Info.Has_Length_Bound
      then
         return "Safe_String_RT.Safe_String";
      elsif Is_Bounded_String_Type (Info) then
         return Bounded_String_Type_Name (Info);
      end if;
      return Ada_Safe_Name (FT.To_String (Info.Name));
   end Render_Type_Name;

   function Render_Subtype_Indication
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
      Base_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Base_Name : constant String := Render_Type_Name (Info);
      Lower_Base_Name : constant String := FT.Lowercase (Base_Name);
   begin
      if not Info.Not_Null then
         return Base_Name;
      elsif Starts_With (Lower_Base_Name, "not null ") then
         return Base_Name;
      elsif Is_Access_Type (Info) or else Is_Access_Type (Base_Info) then
         return "not null " & Base_Name;
      else
         return Base_Name;
      end if;
   end Render_Subtype_Indication;

   function Render_Param_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
      Param_Info : GM.Type_Descriptor := Info;
   begin
      if Param_Info.Anonymous and then Is_Alias_Access (Param_Info) then
         Param_Info.Not_Null := True;
      end if;
      return Render_Subtype_Indication (Unit, Document, Param_Info);
   end Render_Param_Type_Name;

   function Render_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return String
   is
   begin
      if Has_Type (Unit, Document, Name) then
         return Render_Type_Name (Lookup_Type (Unit, Document, Name));
      end if;
      return Ada_Safe_Name (Name);
   end Render_Type_Name;

   function Default_Value_Expr (Type_Name : String) return String is
   begin
      if Type_Name = "boolean" then
         return "false";
      elsif Type_Name = "string" then
         return "Safe_String_RT.Empty";
      elsif Type_Name = "float" or else Type_Name = "long_float" then
         return "0.0";
      elsif Starts_With (Type_Name, "access ")
        or else Starts_With (Type_Name, "not null access ")
        or else Starts_With (Type_Name, "access constant ")
        or else Starts_With (Type_Name, "not null access constant ")
      then
         return "null";
      end if;
      return Ada_Safe_Name (Type_Name) & "'First";
   end Default_Value_Expr;

   function Default_Value_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
      Type_Name : constant String := Render_Type_Name (Info);
      Kind      : constant String := FT.To_String (Info.Kind);
      Result    : SU.Unbounded_String;
   begin
      if Is_Bounded_String_Type (Info) then
         return Bounded_String_Instance_Name (Info) & ".Empty";
      elsif FT.Lowercase (Kind) = "string" then
         return "Safe_String_RT.Empty";
      elsif FT.Lowercase (Kind) = "array" and then Info.Growable then
         return Array_Runtime_Instance_Name (Info) & ".Empty";
      elsif Kind = "access" then
         return "null";
      elsif Kind = "array" and then not Info.Index_Types.Is_Empty then
         Result := SU.To_Unbounded_String ("");
         for Index in 1 .. Natural (Info.Index_Types.Length) loop
            Result := Result & SU.To_Unbounded_String ("(others => ");
         end loop;
         Result :=
           Result
           & SU.To_Unbounded_String
               (Default_Value_Expr
                  (Unit,
                   Document,
                   Resolve_Type_Name
                     (Unit,
                      Document,
                      FT.To_String (Info.Component_Type))));
         for Index in 1 .. Natural (Info.Index_Types.Length) loop
            Result := Result & SU.To_Unbounded_String (")");
         end loop;
         return SU.To_String (Result);
      elsif Kind = "record" then
         Result := SU.To_Unbounded_String ("(");
         for Index in Info.Fields.First_Index .. Info.Fields.Last_Index loop
            if Index /= Info.Fields.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Info.Fields (Index).Name)
                   & " => "
                   & Default_Value_Expr
                       (Unit,
                        Document,
                        Resolve_Type_Name
                          (Unit,
                           Document,
                           FT.To_String (Info.Fields (Index).Type_Name))));
         end loop;
         Result := Result & SU.To_Unbounded_String (")");
         return SU.To_String (Result);
      elsif Is_Tuple_Type (Info) then
         declare
            First_Association : Boolean := True;
         begin
            Result := SU.To_Unbounded_String ("(");
            for Index in Info.Tuple_Element_Types.First_Index .. Info.Tuple_Element_Types.Last_Index loop
               if not First_Association then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Tuple_Field_Name (Positive (Index))
                     & " => "
                     & Default_Value_Expr
                         (Unit,
                          Document,
                          Resolve_Type_Name
                            (Unit,
                             Document,
                             FT.To_String (Info.Tuple_Element_Types (Index)))));
               First_Association := False;
            end loop;
         end;
         Result := Result & SU.To_Unbounded_String (")");
         return SU.To_String (Result);
      elsif Is_Result_Builtin (Info) then
         return Render_Result_Empty_Aggregate;
      end if;
      return Default_Value_Expr (Type_Name);
   end Default_Value_Expr;

   function Default_Value_Expr (Info : GM.Type_Descriptor) return String is
      Type_Name : constant String := Render_Type_Name (Info);
      Kind      : constant String := FT.To_String (Info.Kind);
      Result    : SU.Unbounded_String;
   begin
      if Is_Bounded_String_Type (Info) then
         return Bounded_String_Instance_Name (Info) & ".Empty";
      elsif FT.Lowercase (Kind) = "string" then
         return "Safe_String_RT.Empty";
      elsif FT.Lowercase (Kind) = "array" and then Info.Growable then
         return Array_Runtime_Instance_Name (Info) & ".Empty";
      elsif Kind = "access" then
         return "null";
      elsif Kind = "array" and then not Info.Index_Types.Is_Empty then
         Result := SU.To_Unbounded_String ("");
         for Index in 1 .. Natural (Info.Index_Types.Length) loop
            Result := Result & SU.To_Unbounded_String ("(others => ");
         end loop;
         Result :=
           Result
           & SU.To_Unbounded_String (Default_Value_Expr (FT.To_String (Info.Component_Type)));
         for Index in 1 .. Natural (Info.Index_Types.Length) loop
            Result := Result & SU.To_Unbounded_String (")");
         end loop;
         return SU.To_String (Result);
      elsif Kind = "record" then
         Result := SU.To_Unbounded_String ("(");
         for Index in Info.Fields.First_Index .. Info.Fields.Last_Index loop
            if Index /= Info.Fields.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Info.Fields (Index).Name)
                   & " => "
                   & Default_Value_Expr (FT.To_String (Info.Fields (Index).Type_Name)));
         end loop;
         Result := Result & SU.To_Unbounded_String (")");
         return SU.To_String (Result);
      elsif Is_Tuple_Type (Info) then
         declare
            First_Association : Boolean := True;
         begin
            Result := SU.To_Unbounded_String ("(");
            for Index in Info.Tuple_Element_Types.First_Index .. Info.Tuple_Element_Types.Last_Index loop
               if not First_Association then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Tuple_Field_Name (Positive (Index))
                     & " => "
                     & Default_Value_Expr (FT.To_String (Info.Tuple_Element_Types (Index))));
               First_Association := False;
            end loop;
         end;
         Result := Result & SU.To_Unbounded_String (")");
         return SU.To_String (Result);
      elsif Is_Result_Builtin (Info) then
         return Render_Result_Empty_Aggregate;
      end if;
      return Default_Value_Expr (Type_Name);
   end Default_Value_Expr;

   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl
   is
   begin
      for Item of Unit.Channels loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      for Item of Unit.Imported_Channels loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Lookup_Channel;

   procedure Collect_Synthetic_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector)
   is
      Seen      : FT.UString_Vectors.Vector;
      Processed : FT.UString_Vectors.Vector;

      procedure Add_From_Info (Info : GM.Type_Descriptor);
      procedure Add_From_Statements (Statements : CM.Statement_Access_Vectors.Vector);

      procedure Add_Unique (Info : GM.Type_Descriptor) is
      begin
         if Has_Text (Info.Name)
           and then not Contains_Name (Seen, FT.To_String (Info.Name))
         then
            Seen.Append (Info.Name);
            Result.Append (Info);
         end if;
      end Add_Unique;

      procedure Add_From_Name (Name : String) is
      begin
         if Name'Length = 0 then
            return;
         elsif Has_Type (Unit, Document, Name) then
            Add_From_Info (Lookup_Type (Unit, Document, Name));
         elsif Starts_With (Name, "__bounded_string_") then
            declare
               Found : Boolean := False;
               Info  : GM.Type_Descriptor := (others => <>);
            begin
               Info := Synthetic_Bounded_String_Type (Name, Found);
               if Found then
                  Add_From_Info (Info);
               end if;
            end;
         elsif FT.Lowercase (Name) = "result" then
            Add_From_Info (BT.Result_Type);
         elsif Starts_With (Name, "__tuple") then
            declare
               Info : GM.Type_Descriptor;
            begin
               Info.Name := FT.To_UString (Name);
               Info.Kind := FT.To_UString ("tuple");
               Add_Unique (Info);
            end;
         end if;
      end Add_From_Name;

      procedure Add_From_Info (Info : GM.Type_Descriptor) is
         Name_Text : constant String := FT.To_String (Info.Name);
      begin
         if not Has_Text (Info.Name)
           or else Contains_Name (Processed, Name_Text)
         then
            return;
         end if;

         Processed.Append (Info.Name);

         if Info.Has_Base then
            Add_From_Name (FT.To_String (Info.Base));
         end if;
         if Info.Has_Component_Type then
            Add_From_Name (FT.To_String (Info.Component_Type));
         end if;
         if Info.Has_Target then
            Add_From_Name (FT.To_String (Info.Target));
         end if;
         for Item of Info.Tuple_Element_Types loop
            Add_From_Name (FT.To_String (Item));
         end loop;
         for Field of Info.Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
         for Field of Info.Variant_Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;

         if (FT.To_String (Info.Kind) = "subtype" and then not Info.Discriminant_Constraints.Is_Empty)
           or else (FT.To_String (Info.Kind) = "subtype"
                    and then Starts_With (FT.To_String (Info.Name), "__constraint")
                    and then Info.Has_Base
                    and then Info.Has_Low
                    and then Info.Has_High)
           or else Is_Tuple_Type (Info)
           or else Is_Result_Builtin (Info)
         then
            Add_Unique (Info);
         end if;
      end Add_From_Info;

      procedure Add_From_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector) is
      begin
         for Decl of Decls loop
            Add_From_Info (Decl.Type_Info);
         end loop;
      end Add_From_Decls;

      procedure Add_From_Statements (Statements : CM.Statement_Access_Vectors.Vector) is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Object_Decl =>
                     Add_From_Info (Item.Decl.Type_Info);
                  when CM.Stmt_Destructure_Decl =>
                     Add_From_Info (Item.Destructure.Type_Info);
                  when CM.Stmt_If =>
                     Add_From_Statements (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Add_From_Statements (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Add_From_Statements (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     for Arm of Item.Case_Arms loop
                        Add_From_Statements (Arm.Statements);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_Loop =>
                     Add_From_Statements (Item.Body_Stmts);
                  when CM.Stmt_For =>
                     if Item.Loop_Iterable /= null then
                        declare
                           Found : Boolean := False;
                           One_Char_Info : GM.Type_Descriptor := (others => <>);
                        begin
                           One_Char_Info :=
                             Synthetic_Bounded_String_Type ("__bounded_string_1", Found);
                           if Found then
                              Add_From_Info (One_Char_Info);
                           end if;
                        end;
                     end if;
                     Add_From_Statements (Item.Body_Stmts);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Add_From_Info (Arm.Channel_Data.Type_Info);
                              Add_From_Statements (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Add_From_Statements (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Add_From_Statements;
   begin
      for Item of Unit.Types loop
         Add_From_Info (Item);
      end loop;
      for Item of Unit.Objects loop
         Add_From_Info (Item.Type_Info);
      end loop;
      for Item of Unit.Channels loop
         Add_From_Info (Item.Element_Type);
      end loop;
      for Item of Unit.Subprograms loop
         for Param of Item.Params loop
            Add_From_Info (Param.Type_Info);
         end loop;
         if Item.Has_Return_Type then
            Add_From_Info (Item.Return_Type);
         end if;
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
      for Item of Unit.Tasks loop
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
   end Collect_Synthetic_Types;

   procedure Collect_Bounded_String_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State)
   is
      Processed : FT.UString_Vectors.Vector;

      procedure Add_From_Info (Info : GM.Type_Descriptor);

      procedure Add_From_Name (Name : String) is
      begin
         if Name'Length = 0 then
            null;
         elsif Has_Type (Unit, Document, Name) then
            Add_From_Info (Lookup_Type (Unit, Document, Name));
         elsif Starts_With (Name, "__bounded_string_") then
            declare
               Found : Boolean := False;
               Info  : GM.Type_Descriptor := (others => <>);
            begin
               Info := Synthetic_Bounded_String_Type (Name, Found);
               if Found then
                  Add_From_Info (Info);
               end if;
            end;
         end if;
      end Add_From_Name;

      procedure Add_From_Info (Info : GM.Type_Descriptor) is
         Name_Text : constant String := FT.To_String (Info.Name);
      begin
         if Has_Text (Info.Name)
           and then Contains_Name (Processed, Name_Text)
         then
            return;
         elsif Has_Text (Info.Name) then
            Processed.Append (Info.Name);
         end if;

         Register_Bounded_String_Type (State, Info);
         if Info.Has_Base then
            Add_From_Name (FT.To_String (Info.Base));
         end if;
         if Info.Has_Component_Type then
            Add_From_Name (FT.To_String (Info.Component_Type));
         end if;
         if Info.Has_Target then
            Add_From_Name (FT.To_String (Info.Target));
         end if;
         for Item of Info.Tuple_Element_Types loop
            Add_From_Name (FT.To_String (Item));
         end loop;
         for Field of Info.Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
         for Field of Info.Variant_Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
      end Add_From_Info;

      procedure Add_From_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector) is
      begin
         for Decl of Decls loop
            Add_From_Info (Decl.Type_Info);
         end loop;
      end Add_From_Decls;

      procedure Add_From_Statements (Statements : CM.Statement_Access_Vectors.Vector) is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Object_Decl =>
                     Add_From_Info (Item.Decl.Type_Info);
                  when CM.Stmt_Destructure_Decl =>
                     Add_From_Info (Item.Destructure.Type_Info);
                  when CM.Stmt_If =>
                     Add_From_Statements (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Add_From_Statements (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Add_From_Statements (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     for Arm of Item.Case_Arms loop
                        Add_From_Statements (Arm.Statements);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_Loop =>
                     Add_From_Statements (Item.Body_Stmts);
                  when CM.Stmt_For =>
                     if Item.Loop_Iterable /= null then
                        declare
                           Found : Boolean := False;
                           One_Char_Info : GM.Type_Descriptor := (others => <>);
                        begin
                           One_Char_Info :=
                             Synthetic_Bounded_String_Type ("__bounded_string_1", Found);
                           if Found then
                              Add_From_Info (One_Char_Info);
                           end if;
                        end;
                     end if;
                     Add_From_Statements (Item.Body_Stmts);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Add_From_Info (Arm.Channel_Data.Type_Info);
                              Add_From_Statements (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Add_From_Statements (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Add_From_Statements;
   begin
      for Item of Unit.Types loop
         Add_From_Info (Item);
      end loop;
      for Item of Unit.Objects loop
         Add_From_Info (Item.Type_Info);
      end loop;
      for Item of Unit.Channels loop
         Add_From_Info (Item.Element_Type);
      end loop;
      for Item of Unit.Subprograms loop
         for Param of Item.Params loop
            Add_From_Info (Param.Type_Info);
         end loop;
         if Item.Has_Return_Type then
            Add_From_Info (Item.Return_Type);
         end if;
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
      for Item of Unit.Tasks loop
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
      Add_From_Statements (Unit.Statements);
   end Collect_Bounded_String_Types;

   procedure Collect_Owner_Access_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector)
   is
      pragma Unreferenced (Document);
      Seen : FT.UString_Vectors.Vector;

      procedure Add_From_Info (Info : GM.Type_Descriptor);
      procedure Add_From_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector);
      procedure Add_From_Decls (Decls : CM.Object_Decl_Vectors.Vector);
      procedure Add_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector);

      procedure Add_From_Info (Info : GM.Type_Descriptor) is
         Name_Text : constant String := FT.To_String (Info.Name);
      begin
         if not Is_Owner_Access (Info) or else Name_Text'Length = 0 then
            null;
         elsif Contains_Name (Seen, Name_Text) then
            return;
         else
            Seen.Append (Info.Name);
            Result.Append (Info);
         end if;
      end Add_From_Info;

      procedure Add_From_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector) is
      begin
         for Decl of Decls loop
            Add_From_Info (Decl.Type_Info);
         end loop;
      end Add_From_Decls;

      procedure Add_From_Decls (Decls : CM.Object_Decl_Vectors.Vector) is
      begin
         for Decl of Decls loop
            Add_From_Info (Decl.Type_Info);
         end loop;
      end Add_From_Decls;

      procedure Add_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector) is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Object_Decl =>
                     Add_From_Info (Item.Decl.Type_Info);
                  when CM.Stmt_Destructure_Decl =>
                     Add_From_Info (Item.Destructure.Type_Info);
                  when CM.Stmt_If =>
                     Add_From_Statements (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Add_From_Statements (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Add_From_Statements (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     for Arm of Item.Case_Arms loop
                        Add_From_Statements (Arm.Statements);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     Add_From_Decls (Item.Declarations);
                     Add_From_Statements (Item.Body_Stmts);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Add_From_Info (Arm.Channel_Data.Type_Info);
                              Add_From_Statements (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Add_From_Statements (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Add_From_Statements;
   begin
      for Item of Unit.Types loop
         Add_From_Info (Item);
      end loop;
      for Item of Unit.Objects loop
         Add_From_Info (Item.Type_Info);
      end loop;
      for Item of Unit.Subprograms loop
         for Param of Item.Params loop
            Add_From_Info (Param.Type_Info);
         end loop;
         if Item.Has_Return_Type then
            Add_From_Info (Item.Return_Type);
         end if;
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
      for Item of Unit.Tasks loop
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
   end Collect_Owner_Access_Helper_Types;

   procedure Render_Owner_Access_Helper_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor)
   is
      Type_Name   : constant String := Render_Type_Name (Type_Item);
      Target_Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Target));
      Result_Info : GM.Type_Descriptor := Type_Item;
   begin
      if not Is_Owner_Access (Type_Item) or else not Type_Item.Has_Target then
         return;
      end if;

      Result_Info.Not_Null := True;

      Append_Line
        (Buffer,
         "function "
         & Local_Allocate_Helper_Name (Type_Item)
         & " (Value : "
         & Target_Name
         & ") return "
         & Render_Subtype_Indication (Unit, Document, Result_Info)
         & ASCII.LF
         & Indentation (2)
         & "with Post => "
         & Local_Allocate_Helper_Name (Type_Item)
         & "'Result /= null;",
         1);
      Append_Line
        (Buffer,
         "procedure "
         & Local_Free_Helper_Name (Type_Item)
         & " (Value : in out "
         & Type_Name
         & ")"
         & ASCII.LF
         & Indentation (2)
         & "with Always_Terminates,"
         & ASCII.LF
         & Indentation (3)
         & "Post => Value = null;",
         1);
      Append_Line
        (Buffer,
         "function "
         & Local_Dispose_Helper_Name (Type_Item)
         & " (Value : "
         & Type_Name
         & ") return Boolean"
         & ";",
         1);
      Append_Line (Buffer);
   end Render_Owner_Access_Helper_Spec;

   procedure Render_Owner_Access_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State)
   is
      Type_Name   : constant String := Render_Type_Name (Type_Item);
      Target_Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Target));
      Result_Info : GM.Type_Descriptor := Type_Item;
      Generic_Free_Name : constant String :=
        Local_Free_Helper_Name (Type_Item) & "_Access";
   begin
      if not Is_Owner_Access (Type_Item) or else not Type_Item.Has_Target then
         return;
      end if;

      Result_Info.Not_Null := True;
      State.Needs_Unchecked_Deallocation := True;

      Append_Line
        (Buffer,
         "function "
         & Local_Allocate_Helper_Name (Type_Item)
         & " (Value : "
         & Target_Name
         & ") return "
         & Render_Subtype_Indication (Unit, Document, Result_Info)
         & " with SPARK_Mode => Off is",
         1);
      Append_Line (Buffer, "begin", 1);
      Append_Line
        (Buffer,
         "return new " & Target_Name & "'(Value);",
         2);
      Append_Line
        (Buffer,
         "end " & Local_Allocate_Helper_Name (Type_Item) & ";",
         1);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "procedure "
         & Local_Free_Helper_Name (Type_Item)
         & " (Value : in out "
         & Type_Name
         & ") with SPARK_Mode => Off is",
         1);
      Append_Line
        (Buffer,
         "procedure "
         & Generic_Free_Name
         & " is new Ada.Unchecked_Deallocation ("
         & Target_Name
         & ", "
         & Type_Name
         & ");",
         2);
      Append_Line (Buffer, "begin", 1);
      Append_Line (Buffer, "if Value /= null then", 2);
      Append_Line (Buffer, Generic_Free_Name & " (Value);", 3);
      Append_Line (Buffer, "end if;", 2);
      Append_Line (Buffer, "Value := null;", 2);
      Append_Line
        (Buffer,
         "end " & Local_Free_Helper_Name (Type_Item) & ";",
         1);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "function "
         & Local_Dispose_Helper_Name (Type_Item)
         & " (Value : "
         & Type_Name
         & ") return Boolean with SPARK_Mode => Off is",
         1);
      Append_Line (Buffer, "Local_Copy : " & Type_Name & " := Value;", 2);
      Append_Line (Buffer, "begin", 1);
      Append_Line (Buffer, Local_Free_Helper_Name (Type_Item) & " (Local_Copy);", 2);
      Append_Line (Buffer, "return True;", 2);
      Append_Line
        (Buffer,
         "end " & Local_Dispose_Helper_Name (Type_Item) & ";",
         1);
      Append_Line (Buffer);
   end Render_Owner_Access_Helper_Body;

   procedure Append_Bounded_String_Instantiations
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State)
   is
   begin
      for Item of State.Bounded_String_Bounds loop
         Append_Line
           (Buffer,
            "package "
            & Bounded_String_Instance_Name (Natural'Value (FT.To_String (Item)))
            & " is new Safe_Bounded_Strings.Generic_Bounded_String (Capacity => "
            & FT.To_String (Item)
            & ");",
            1);
         Append_Line
           (Buffer,
            "subtype "
            & Bounded_String_Type_Name (Natural'Value (FT.To_String (Item)))
            & " is "
            & Bounded_String_Instance_Name (Natural'Value (FT.To_String (Item)))
            & ".Bounded_String;",
            1);
      end loop;
      if not State.Bounded_String_Bounds.Is_Empty then
         Append_Line (Buffer);
      end if;
   end Append_Bounded_String_Instantiations;

   procedure Append_Bounded_String_Uses
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural)
   is
   begin
      for Item of State.Bounded_String_Bounds loop
         Append_Line
           (Buffer,
            "use " & Bounded_String_Instance_Name (Natural'Value (FT.To_String (Item))) & ";",
            Depth);
      end loop;
      if not State.Bounded_String_Bounds.Is_Empty then
         Append_Line (Buffer);
      end if;
   end Append_Bounded_String_Uses;

   function Render_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Kind : constant String := FT.To_String (Type_Item.Kind);
      Result : SU.Unbounded_String;

      function Render_Type_Name_From_Text (Name_Text : String) return String is
         Info  : GM.Type_Descriptor := (others => <>);
         Found : Boolean := False;
      begin
         if FT.Lowercase (Name_Text) = "string" then
            State.Needs_Safe_String_RT := True;
            return "Safe_String_RT.Safe_String";
         end if;
         Info := Synthetic_Bounded_String_Type (Name_Text, Found);
         if Found then
            Register_Bounded_String_Type (State, Info);
            return Bounded_String_Type_Name (Info);
         end if;
         return Ada_Safe_Name (Name_Text);
      end Render_Type_Name_From_Text;
   begin
      if Kind = "incomplete" then
         return "type " & Name & ";";
      elsif Kind = "integer" then
         return
           "type "
           & Name
           & " is range "
           & Trim_Image (Type_Item.Low)
           & " .. "
           & Trim_Image (Type_Item.High)
           & ";";
      elsif Kind = "binary" then
         return
           "type "
           & Name
           & " is mod 2 ** "
           & Ada.Strings.Fixed.Trim (Positive'Image (Type_Item.Bit_Width), Ada.Strings.Both)
           & ";";
      elsif Kind = "subtype" then
         if not Type_Item.Discriminant_Constraints.Is_Empty then
            Result :=
              SU.To_Unbounded_String
                ("subtype "
                 & Ada_Safe_Name (Name)
                 & " is "
                 & Ada_Safe_Name (FT.To_String (Type_Item.Base))
                 & " (");
            for Index in Type_Item.Discriminant_Constraints.First_Index .. Type_Item.Discriminant_Constraints.Last_Index loop
               declare
                  Constraint : constant GM.Discriminant_Constraint :=
                    Type_Item.Discriminant_Constraints (Index);
               begin
                  if Index /= Type_Item.Discriminant_Constraints.First_Index then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  if Constraint.Is_Named then
                     Result :=
                       Result
                       & SU.To_Unbounded_String
                           (FT.To_String (Constraint.Name) & " => ");
                  end if;
                  Result :=
                    Result & SU.To_Unbounded_String (Render_Scalar_Value (Constraint.Value));
               end;
            end loop;
            Result := Result & SU.To_Unbounded_String (");");
            return SU.To_String (Result);
         elsif Type_Item.Has_Low and then Type_Item.Has_High then
            return
              "subtype "
              & Ada_Safe_Name (Name)
              & " is "
              & Ada_Safe_Name (FT.To_String (Type_Item.Base))
              & " range "
              & Trim_Image (Type_Item.Low)
              & " .. "
              & Trim_Image (Type_Item.High)
              & ";";
         elsif Is_Builtin_Integer_Name (FT.To_String (Type_Item.Base))
           or else Is_Builtin_Float_Name (FT.To_String (Type_Item.Base))
         then
            return
              "subtype " & Ada_Safe_Name (Name) & " is " & Ada_Safe_Name (FT.To_String (Type_Item.Base)) & ";";
         else
            return
              "subtype " & Ada_Safe_Name (Name) & " is " & Ada_Safe_Name (FT.To_String (Type_Item.Base)) & ";";
         end if;
      elsif Kind = "array" then
         if Type_Item.Growable or else Type_Item.Index_Types.Is_Empty then
            State.Needs_Safe_Array_RT := True;
            return
              "function "
              & Array_Runtime_Default_Element_Name (Type_Item)
              & " return "
              & Render_Type_Name_From_Text (FT.To_String (Type_Item.Component_Type))
              & ";"
              & ASCII.LF
              & Indentation (1)
              & "function "
              & Array_Runtime_Clone_Element_Name (Type_Item)
              & " (Source : "
              & Render_Type_Name_From_Text (FT.To_String (Type_Item.Component_Type))
              & ") return "
              & Render_Type_Name_From_Text (FT.To_String (Type_Item.Component_Type))
              & ";"
              & ASCII.LF
              & Indentation (1)
              & "procedure "
              & Array_Runtime_Free_Element_Name (Type_Item)
              & " (Value : in out "
              & Render_Type_Name_From_Text (FT.To_String (Type_Item.Component_Type))
              & ");"
              & ASCII.LF
              & Indentation (1)
              & "package "
              & Array_Runtime_Instance_Name (Type_Item)
              & " is new Safe_Array_RT"
              & ASCII.LF
              & Indentation (2)
              & "(Element_Type => "
              & Render_Type_Name_From_Text (FT.To_String (Type_Item.Component_Type))
              & ","
              & ASCII.LF
              & Indentation (3)
              & "Default_Element => "
              & Array_Runtime_Default_Element_Name (Type_Item)
              & ","
              & ASCII.LF
              & Indentation (3)
              & "Clone_Element => "
              & Array_Runtime_Clone_Element_Name (Type_Item)
              & ","
              & ASCII.LF
              & Indentation (3)
              & "Free_Element => "
              & Array_Runtime_Free_Element_Name (Type_Item)
              & ");"
              & ASCII.LF
              & Indentation (1)
              & "subtype "
              & Ada_Safe_Name (Name)
              & " is "
              & Array_Runtime_Instance_Name (Type_Item)
              & ".Safe_Array;";
         end if;
         return
           "type "
           & Ada_Safe_Name (Name)
           & " is array ("
           & Join_Names (Type_Item.Index_Types)
           & ") of "
           & Render_Type_Name_From_Text (FT.To_String (Type_Item.Component_Type))
           & ";";
      elsif Kind = "tuple" then
         Result := SU.To_Unbounded_String ("type " & Ada_Safe_Name (Name));
         Result := Result & SU.To_Unbounded_String (" is record" & ASCII.LF);
         for Index in Type_Item.Tuple_Element_Types.First_Index .. Type_Item.Tuple_Element_Types.Last_Index loop
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Indentation (1)
                   & Tuple_Field_Name (Positive (Index))
                   & " : "
                   & Render_Type_Name_From_Text (FT.To_String (Type_Item.Tuple_Element_Types (Index)))
                   & ";"
                   & ASCII.LF);
         end loop;
         Result := Result & SU.To_Unbounded_String ("end record;");
         return SU.To_String (Result);
      elsif Is_Result_Builtin (Type_Item) then
         State.Needs_Ada_Strings_Unbounded := True;
         return
           "type "
           & Ada_Safe_Name (Name)
           & " is record"
           & ASCII.LF
           & Indentation (1)
           & "Ok : Boolean := True;"
           & ASCII.LF
           & Indentation (1)
           & "Message : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.Null_Unbounded_String;"
           & ASCII.LF
           & Indentation (1)
           & "end record;";
      elsif Kind = "record" then
         declare
            function Is_Variant_Field_Name (Field_Name : String) return Boolean is
            begin
               for Field of Type_Item.Variant_Fields loop
                  if FT.To_String (Field.Name) = Field_Name then
                     return True;
                  end if;
               end loop;
               return False;
            end Is_Variant_Field_Name;

            function Same_Choice
              (Left, Right : GM.Variant_Field) return Boolean is
            begin
               return Left.Is_Others = Right.Is_Others
                 and then
                   (if Left.Is_Others
                    then True
                    else Left.Choice.Kind = Right.Choice.Kind
                      and then Render_Scalar_Value (Left.Choice) = Render_Scalar_Value (Right.Choice));
            end Same_Choice;

            procedure Append_Field_Line
              (Field_Name : String;
               Field_Type : String;
               Depth      : Natural) is
            begin
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Indentation (Depth)
                      & Field_Name
                      & " : "
                      & Field_Type
                      & ";"
                      & ASCII.LF);
            end Append_Field_Line;
         begin
            Result := SU.To_Unbounded_String ("type " & Name);
            if not Type_Item.Discriminants.Is_Empty then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" (");
               for Index in Type_Item.Discriminants.First_Index .. Type_Item.Discriminants.Last_Index loop
                  declare
                     Disc : constant GM.Discriminant_Descriptor :=
                       Type_Item.Discriminants (Index);
                  begin
                     if Index /= Type_Item.Discriminants.First_Index then
                        Result := Result & SU.To_Unbounded_String ("; ");
                     end if;
                     Result :=
                       Result
                       & SU.To_Unbounded_String
                           (FT.To_String (Disc.Name)
                            & " : "
                            & Ada_Safe_Name (FT.To_String (Disc.Type_Name))
                            & (if Disc.Has_Default
                               then " := " & Render_Scalar_Value (Disc.Default_Value)
                               else ""));
                  end;
               end loop;
               Result := Result & SU.To_Unbounded_String (")");
            elsif Type_Item.Has_Discriminant then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" ("
                      & FT.To_String (Type_Item.Discriminant_Name)
                      & " : "
                      & Ada_Safe_Name (FT.To_String (Type_Item.Discriminant_Type))
                      & (if Type_Item.Has_Discriminant_Default
                         then " := " & (if Type_Item.Discriminant_Default_Bool then "true" else "false")
                         else "")
                      & ")");
            end if;
            Result := Result & SU.To_Unbounded_String (" is record" & ASCII.LF);
            for Field of Type_Item.Fields loop
               if not Is_Variant_Field_Name (FT.To_String (Field.Name)) then
                  Append_Field_Line
                    (FT.To_String (Field.Name),
                     Render_Type_Name_From_Text (FT.To_String (Field.Type_Name)),
                     1);
               end if;
            end loop;
            if not Type_Item.Variant_Fields.Is_Empty then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Indentation (1)
                      & "case "
                      & FT.To_String
                          ((if Has_Text (Type_Item.Variant_Discriminant_Name)
                            then Type_Item.Variant_Discriminant_Name
                            else Type_Item.Discriminant_Name))
                      & " is"
                      & ASCII.LF);
               declare
                  Index : Positive := Type_Item.Variant_Fields.First_Index;
               begin
                  while Index <= Type_Item.Variant_Fields.Last_Index loop
                     declare
                        First_Field : constant GM.Variant_Field :=
                          Type_Item.Variant_Fields (Index);
                     begin
                        Result :=
                          Result
                          & SU.To_Unbounded_String
                              (Indentation (1)
                               & "when "
                               & (if First_Field.Is_Others
                                  then "others"
                                  else Render_Scalar_Value (First_Field.Choice))
                               & " =>"
                               & ASCII.LF);
                        loop
                           Append_Field_Line
                             (FT.To_String (Type_Item.Variant_Fields (Index).Name),
                              Render_Type_Name_From_Text
                                (FT.To_String (Type_Item.Variant_Fields (Index).Type_Name)),
                              2);
                           exit when Index = Type_Item.Variant_Fields.Last_Index;
                           exit when not Same_Choice
                             (First_Field,
                              Type_Item.Variant_Fields (Index + 1));
                           Index := Index + 1;
                        end loop;
                        Index := Index + 1;
                     end;
                  end loop;
               end;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Indentation (1) & "end case;" & ASCII.LF);
            end if;
            Result :=
              Result & SU.To_Unbounded_String ("end record;");
            return SU.To_String (Result);
         end;
      elsif Kind = "access" then
         declare
            Target_Name : constant String := FT.To_String (Type_Item.Target);
            Target_Decl : constant String :=
              (if Target_Name'Length > 0
                  and then Starts_With (Target_Name, "safe_ref_target_")
               then "type " & Target_Name & ";" & ASCII.LF
               else "");
         begin
            return
              Target_Decl
              & "type "
              & Name
              & " is "
              & (if Type_Item.Not_Null then "not null " else "")
              & "access "
              & (if Type_Item.Is_Constant then "constant " else "")
              & Target_Name
              & ";";
         end;
      elsif Kind = "float" then
         if Type_Item.Has_Digits_Text then
            return
              "type "
              & Name
              & " is digits "
              & FT.To_String (Type_Item.Digits_Text)
              & (if Type_Item.Has_Float_Low_Text and then Type_Item.Has_Float_High_Text
                  then
                    " range "
                    & FT.To_String (Type_Item.Float_Low_Text)
                    & " .. "
                    & FT.To_String (Type_Item.Float_High_Text)
                  else
                    "")
              & ";";
         end if;
         return "type " & Name & " is digits 6;";
      end if;

      Raise_Unsupported
        (State,
         FT.Null_Span,
         "PR09 emitter does not yet support type kind '" & Kind & "'");
   end Render_Type_Decl;

   procedure Render_Growable_Array_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State)
   is
   begin
      if FT.To_String (Type_Item.Kind) /= "array" or else not Type_Item.Growable then
         return;
      end if;

      declare
         Component_Info : constant GM.Type_Descriptor :=
           Resolve_Type_Name
             (Unit,
              Document,
              FT.To_String (Type_Item.Component_Type));
         Component_Name : constant String := Render_Type_Name (Component_Info);
         Default_Image  : constant String := Default_Value_Expr (Component_Info);
         Clone_Image    : SU.Unbounded_String := SU.To_Unbounded_String ("Source");
      begin
         if Is_Plain_String_Type (Unit, Document, Component_Info) then
            State.Needs_Safe_String_RT := True;
            Clone_Image := SU.To_Unbounded_String ("Safe_String_RT.Clone (Source)");
         elsif Is_Growable_Array_Type (Unit, Document, Component_Info) then
            State.Needs_Safe_Array_RT := True;
            Clone_Image :=
              SU.To_Unbounded_String
                (Array_Runtime_Instance_Name (Component_Info) & ".Clone (Source)");
         end if;

         Append_Line
           (Buffer,
            "function "
            & Array_Runtime_Default_Element_Name (Type_Item)
            & " return "
            & Component_Name
            & " is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "return " & Default_Image & ";", 2);
         Append_Line
           (Buffer,
            "end " & Array_Runtime_Default_Element_Name (Type_Item) & ";",
            1);
         Append_Line (Buffer);

         Append_Line
           (Buffer,
            "function "
            & Array_Runtime_Clone_Element_Name (Type_Item)
            & " (Source : "
            & Component_Name
            & ") return "
            & Component_Name
            & " is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "return " & SU.To_String (Clone_Image) & ";", 2);
         Append_Line
           (Buffer,
            "end " & Array_Runtime_Clone_Element_Name (Type_Item) & ";",
            1);
         Append_Line (Buffer);

         Append_Line
           (Buffer,
            "procedure "
            & Array_Runtime_Free_Element_Name (Type_Item)
            & " (Value : in out "
            & Component_Name
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         if Is_Plain_String_Type (Unit, Document, Component_Info) then
            State.Needs_Safe_String_RT := True;
            Append_Line (Buffer, "Safe_String_RT.Free (Value);", 2);
         elsif Is_Growable_Array_Type (Unit, Document, Component_Info) then
            State.Needs_Safe_Array_RT := True;
            Append_Line
              (Buffer,
               Array_Runtime_Instance_Name (Component_Info) & ".Free (Value);",
               2);
         else
            Append_Line (Buffer, "null;", 2);
         end if;
         Append_Line
           (Buffer,
            "end " & Array_Runtime_Free_Element_Name (Type_Item) & ";",
            1);
         Append_Line (Buffer);
      end;
   end Render_Growable_Array_Helper_Body;

   function Map_Operator (Operator : String) return String is
   begin
      if Operator = "!=" then
         return "/=";
      elsif Operator = "==" then
         return "=";
      end if;
      return Operator;
   end Map_Operator;

   function Binary_Result_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return String is
   begin
      if Expr /= null and then Has_Text (Expr.Type_Name) then
         return Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name));
      elsif Expr /= null and then Expr.Left /= null and then Has_Text (Expr.Left.Type_Name) then
         return Render_Type_Name (Unit, Document, FT.To_String (Expr.Left.Type_Name));
      end if;
      Raise_Internal ("binary expression missing result type during Ada emission");
   end Binary_Result_Type_Name;

   function Binary_Base_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return String is
   begin
      if Expr /= null and then Has_Text (Expr.Type_Name) and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Type_Name)) then
         return Binary_Ada_Name (Binary_Bit_Width (Unit, Document, FT.To_String (Expr.Type_Name)));
      elsif Expr /= null and then Expr.Left /= null and then Has_Text (Expr.Left.Type_Name) then
         return Binary_Ada_Name (Binary_Bit_Width (Unit, Document, FT.To_String (Expr.Left.Type_Name)));
      end if;
      Raise_Internal ("binary expression missing base type during Ada emission");
   end Binary_Base_Type_Name;

   function Render_Binary_Unary_Image
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Expr       : CM.Expr_Access;
      Inner_Image : String) return String is
      Result_Type : constant String := Binary_Result_Type_Name (Unit, Document, Expr);
      Base_Type   : constant String := Binary_Base_Type_Name (Unit, Document, Expr);
   begin
      return
        Result_Type
        & " (not "
        & Base_Type
        & " ("
        & Inner_Image
        & "))";
   end Render_Binary_Unary_Image;

   function Render_Binary_Operation_Image
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Left_Image  : String;
      Right_Image : String) return String is
      Operator    : constant String := FT.To_String (Expr.Operator);
      Result_Type : constant String := Binary_Result_Type_Name (Unit, Document, Expr);
      Base_Type   : constant String := Binary_Base_Type_Name (Unit, Document, Expr);
   begin
      if Operator = "<<" or else Operator = ">>" then
         return
           Result_Type
           & " (Interfaces."
           & (if Operator = "<<" then "Shift_Left" else "Shift_Right")
           & " ("
           & Base_Type
           & " ("
           & Left_Image
           & "), Natural ("
           & Right_Image
           & ")))";
      elsif Operator in "==" | "!=" | "<" | "<=" | ">" | ">=" then
         return
           "("
           & Base_Type
           & " ("
           & Left_Image
           & ") "
           & Map_Operator (Operator)
           & " "
           & Base_Type
           & " ("
           & Right_Image
           & "))";
      end if;

      return
        Result_Type
        & " ("
        & Base_Type
        & " ("
        & Left_Image
        & ") "
        & Map_Operator (Operator)
        & " "
        & Base_Type
        & " ("
        & Right_Image
        & "))";
   end Render_Binary_Operation_Image;

   function Render_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Result : SU.Unbounded_String;
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null expression during Ada emission");
      end if;

      case Expr.Kind is
         when CM.Expr_Int =>
            if Has_Text (Expr.Text) then
               return FT.To_String (Expr.Text);
            end if;
            return Trim_Wide_Image (Expr.Int_Value);
         when CM.Expr_Real =>
            if Has_Text (Expr.Text) then
               return FT.To_String (Expr.Text);
            end if;
            Raise_Unsupported
              (State,
               Expr.Span,
               "real literal missing source text");
         when CM.Expr_String =>
            if Has_Text (Expr.Text) then
               return FT.To_String (Expr.Text);
            end if;
            Raise_Unsupported
              (State,
               Expr.Span,
               "text literal missing source text");
         when CM.Expr_Array_Literal =>
            if Has_Text (Expr.Type_Name) then
               declare
                  Literal_Type : constant GM.Type_Descriptor :=
                    Resolve_Type_Name
                      (Unit, Document, FT.To_String (Expr.Type_Name));
               begin
                  if Is_Growable_Array_Type (Unit, Document, Literal_Type) then
                     return
                       Render_Growable_Array_Expr
                         (Unit, Document, Expr, Literal_Type, State);
                  end if;
               end;
            end if;
            Result := SU.To_Unbounded_String ("(");
            for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
               if Index /= Expr.Elements.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Render_Expr
                        (Unit,
                         Document,
                         Expr.Elements (Index),
                         State));
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Bool =>
            return (if Expr.Bool_Value then "true" else "false");
         when CM.Expr_Null =>
            return "null";
         when CM.Expr_Ident =>
            if FT.Lowercase (FT.To_String (Expr.Name)) = "ok"
              and then FT.Lowercase (FT.To_String (Expr.Type_Name)) = "result"
            then
               State.Needs_Ada_Strings_Unbounded := True;
               return Render_Result_Empty_Aggregate;
            end if;
            return Ada_Safe_Name (FT.To_String (Expr.Name));
         when CM.Expr_Select =>
            declare
               Prefix_Image  : constant String := Render_Expr (Unit, Document, Expr.Prefix, State);
               Selected_Prefix : constant String :=
                 (if Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
                  then Prefix_Image & ".all"
                  else Prefix_Image);
               Selector_Name : constant String := FT.To_String (Expr.Selector);
            begin
               if Selector_Name = "length"
                 and then Expr.Prefix /= null
                 and then Has_Text (Expr.Prefix.Type_Name)
               then
                  declare
                     Prefix_Type : GM.Type_Descriptor := (others => <>);
                     Has_Prefix_Type : Boolean := False;
                  begin
                     if Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)) then
                        Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name));
                        Has_Prefix_Type := True;
                     else
                        Prefix_Type :=
                          Synthetic_Bounded_String_Type
                            (FT.To_String (Expr.Prefix.Type_Name), Has_Prefix_Type);
                     end if;
                     if Has_Prefix_Type and then Is_Bounded_String_Type (Prefix_Type) then
                        Register_Bounded_String_Type (State, Prefix_Type);
                        return
                          "Long_Long_Integer ("
                          & Bounded_String_Instance_Name (Prefix_Type)
                          & ".Length ("
                          & Prefix_Image
                          & "))";
                     elsif Has_Prefix_Type
                       and then FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "string"
                     then
                        return Render_String_Length_Expr (Unit, Document, Expr.Prefix, State);
                     elsif Has_Prefix_Type
                       and then FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "array"
                     then
                        if Is_Growable_Array_Type (Unit, Document, Prefix_Type) then
                           State.Needs_Safe_Array_RT := True;
                           return
                             "Long_Long_Integer ("
                             & Array_Runtime_Instance_Name (Prefix_Type)
                             & ".Length ("
                             & Prefix_Image
                             & "))";
                        end if;
                        return "Long_Long_Integer (" & Prefix_Image & "'Length)";
                     end if;
                  end;
               elsif Selector_Name = "access"
                 and then Expr.Prefix /= null
                 and then Has_Text (Expr.Prefix.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
                 and then Is_Access_Type (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
               then
                  return Prefix_Image;
               elsif Is_Attribute_Selector (Selector_Name)
                 and then not
                   (Expr.Prefix /= null
                    and then Expr.Prefix.Kind = CM.Expr_Select
                    and then FT.To_String (Expr.Prefix.Selector) = "all")
                 and then not Selector_Is_Record_Field (Unit, Document, Expr.Prefix, Selector_Name)
               then
                  return Prefix_Image & "'" & Selector_Name;
               elsif Expr.Prefix /= null
                 and then Selector_Name'Length > 0
                 and then Selector_Name (Selector_Name'First) in '0' .. '9'
                 and then Has_Text (Expr.Prefix.Type_Name)
                 and then
                   (Starts_With (FT.To_String (Expr.Prefix.Type_Name), "__tuple")
                    or else
                      (Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
                       and then Is_Tuple_Type
                         (Lookup_Type
                            (Unit,
                             Document,
                             FT.To_String (Expr.Prefix.Type_Name)))))
               then
                  return
                    Prefix_Image
                    & "."
                    & Tuple_Field_Name (Positive (Natural'Value (Selector_Name)));
               elsif Expr.Prefix /= null
                 and then FT.Lowercase (Selector_Name) = "message"
                 and then Has_Text (Expr.Prefix.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
                 and then Is_Result_Builtin
                   (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
               then
                  State.Needs_Ada_Strings_Unbounded := True;
                  return "Ada.Strings.Unbounded.To_String (" & Prefix_Image & ".Message)";
               end if;
               return Selected_Prefix & "." & Selector_Name;
            end;
         when CM.Expr_Resolved_Index =>
            if Expr.Prefix /= null
              and then Has_Text (Expr.Prefix.Type_Name)
            then
               declare
                  Prefix_Type : GM.Type_Descriptor := (others => <>);
                  Has_Prefix_Type : Boolean := False;
               begin
                  if Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)) then
                     Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name));
                     Has_Prefix_Type := True;
                  else
                     Prefix_Type :=
                       Synthetic_Bounded_String_Type
                         (FT.To_String (Expr.Prefix.Type_Name), Has_Prefix_Type);
                  end if;

                  if Has_Prefix_Type
                    and then FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "string"
                  then
                     return Render_String_Expr (Unit, Document, Expr, State);
                  elsif Has_Prefix_Type
                    and then Is_Growable_Array_Type (Unit, Document, Prefix_Type)
                  then
                     return
                       Render_Growable_Array_Expr
                         (Unit, Document, Expr, Prefix_Type, State);
                  elsif Has_Prefix_Type
                    and then FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "array"
                    and then Natural (Expr.Args.Length) = 2
                    and then Natural (Prefix_Type.Index_Types.Length) = 1
                  then
                     return
                       (if Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
                        then Render_Expr (Unit, Document, Expr.Prefix, State) & ".all"
                        else Render_Expr (Unit, Document, Expr.Prefix, State))
                       & " ("
                       & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State)
                       & " .. "
                       & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State)
                       & ")";
                  end if;
               end;
            end if;
            Result :=
              SU.To_Unbounded_String
                ((if Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
                  then Render_Expr (Unit, Document, Expr.Prefix, State) & ".all"
                  else Render_Expr (Unit, Document, Expr.Prefix, State))
                 & " (");
            for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
               if Index /= Expr.Args.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Render_Expr (Unit, Document, Expr.Args (Index), State));
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Conversion =>
            declare
               Target_Image : constant String :=
                 (if Has_Text (Expr.Type_Name)
                     then Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name))
                  elsif Expr.Target /= null
                     then Render_Expr (Unit, Document, Expr.Target, State)
                  else "");
            begin
               return
                 Target_Image
                 & " ("
                 & Render_Expr (Unit, Document, Expr.Inner, State)
                 & ")";
            end;
         when CM.Expr_Call =>
            declare
               Callee_Flat : constant String := CM.Flatten_Name (Expr.Callee);
               Lower_Callee : constant String := FT.Lowercase (Callee_Flat);
               Callee_Image : constant String :=
                 (if Expr.Callee /= null
                   and then Expr.Callee.Kind = CM.Expr_Select
                   and then FT.To_String (Expr.Callee.Selector) = "access"
                   and then Expr.Callee.Prefix /= null
                   and then Has_Text (Expr.Callee.Prefix.Type_Name)
                   and then Has_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name))
                   and then Is_Access_Type
                     (Lookup_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name)))
                  then
                    Render_Expr (Unit, Document, Expr.Callee.Prefix, State)
                  elsif Expr.Callee /= null
                   and then Expr.Callee.Kind = CM.Expr_Select
                   and then Is_Attribute_Selector (FT.To_String (Expr.Callee.Selector))
                   and then not
                     (Expr.Callee.Prefix /= null
                      and then Expr.Callee.Prefix.Kind = CM.Expr_Select
                      and then FT.To_String (Expr.Callee.Prefix.Selector) = "all")
                   and then not
                     Selector_Is_Record_Field
                       (Unit,
                        Document,
                        Expr.Callee.Prefix,
                        FT.To_String (Expr.Callee.Selector))
                  then
                    Render_Expr (Unit, Document, Expr.Callee.Prefix, State)
                    & "'"
                    & FT.To_String (Expr.Callee.Selector)
                  else Render_Expr (Unit, Document, Expr.Callee, State));
            begin
               if Lower_Callee = "ok" and then Expr.Args.Is_Empty then
                  State.Needs_Ada_Strings_Unbounded := True;
                  return Render_Result_Empty_Aggregate;
               elsif Lower_Callee = "fail" and then Natural (Expr.Args.Length) = 1 then
                  State.Needs_Ada_Strings_Unbounded := True;
                  return
                    Render_Result_Fail_Aggregate
                      (Render_String_Expr
                         (Unit,
                          Document,
                          Expr.Args (Expr.Args.First_Index),
                          State));
               end if;
               if Expr.Args.Is_Empty then
                  return Callee_Image;
               end if;
               Result := SU.To_Unbounded_String (Callee_Image & " (");
               for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
                  declare
                     Arg_Image : SU.Unbounded_String;
                     Used_Formal : Boolean := False;
                  begin
                     if Index /= Expr.Args.First_Index then
                        Result := Result & SU.To_Unbounded_String (", ");
                     end if;

                     for Param of Unit.Subprograms loop
                        if FT.Lowercase (FT.To_String (Param.Name)) = Lower_Callee
                          or else
                            FT.Lowercase
                              (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Param.Name)) = Lower_Callee
                        then
                           declare
                              Position : Natural := 0;
                           begin
                              for Formal of Param.Params loop
                                 Position := Position + 1;
                                 exit when Position > Natural (Index);
                                 if Position = Natural (Index) then
                                    if FT.To_String (Formal.Mode) in "" | "in" | "borrow" then
                                       Arg_Image :=
                                         SU.To_Unbounded_String
                                           (Render_Expr_For_Target_Type
                                              (Unit,
                                               Document,
                                               Expr.Args (Index),
                                               Formal.Type_Info,
                                               State));
                                    else
                                       Arg_Image :=
                                         SU.To_Unbounded_String
                                           (Render_Expr (Unit, Document, Expr.Args (Index), State));
                                    end if;
                                    Used_Formal := True;
                                    exit;
                                 end if;
                              end loop;
                           end;
                           exit when Used_Formal;
                        end if;
                     end loop;

                     if not Used_Formal then
                        Arg_Image :=
                          SU.To_Unbounded_String
                            (Render_Expr (Unit, Document, Expr.Args (Index), State));
                     end if;

                     Result := Result & Arg_Image;
                  end;
               end loop;
               Result := Result & SU.To_Unbounded_String (")");
               return SU.To_String (Result);
            end;
         when CM.Expr_Allocator =>
            return "new " & Render_Expr (Unit, Document, Expr.Value, State);
         when CM.Expr_Aggregate =>
            Result := SU.To_Unbounded_String ("(");
            for Index in Expr.Fields.First_Index .. Expr.Fields.Last_Index loop
               declare
                  Field : constant CM.Aggregate_Field := Expr.Fields (Index);
               begin
                  if Index /= Expr.Fields.First_Index then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (FT.To_String (Field.Field_Name)
                         & " => "
                         & Render_Expr (Unit, Document, Field.Expr, State));
               end;
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Tuple =>
            declare
               Is_Array_Target : constant Boolean :=
                 Has_Text (Expr.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Type_Name))
                 and then Is_Array_Type
                   (Unit,
                    Document,
                    Lookup_Type (Unit, Document, FT.To_String (Expr.Type_Name)));
               First_Association : Boolean := True;
            begin
               if Is_Array_Target then
                  return
                    Render_Positional_Tuple_Aggregate
                      (Unit, Document, Expr, State);
               else
                  Result := SU.To_Unbounded_String ("(");
                  for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
                     declare
                        Target_Info : GM.Type_Descriptor := (others => <>);
                        Has_Target  : Boolean := False;
                     begin
                        if Has_Text (Expr.Type_Name)
                          and then Has_Type (Unit, Document, FT.To_String (Expr.Type_Name))
                        then
                           declare
                              Tuple_Info : constant GM.Type_Descriptor :=
                                Lookup_Type (Unit, Document, FT.To_String (Expr.Type_Name));
                           begin
                              if Is_Tuple_Type (Tuple_Info)
                                and then Index <= Tuple_Info.Tuple_Element_Types.Last_Index
                              then
                                 Target_Info :=
                                   Resolve_Type_Name
                                     (Unit,
                                      Document,
                                      FT.To_String (Tuple_Info.Tuple_Element_Types (Index)));
                                 Has_Target := True;
                              end if;
                           end;
                        end if;

                        if not Has_Target
                          and then Expr.Elements (Index) /= null
                          and then Has_Text (Expr.Elements (Index).Type_Name)
                        then
                           Target_Info :=
                             Resolve_Type_Name
                               (Unit,
                                Document,
                                FT.To_String (Expr.Elements (Index).Type_Name));
                           Has_Target := Has_Text (Target_Info.Name);
                        end if;

                        if not First_Association then
                           Result := Result & SU.To_Unbounded_String (", ");
                        end if;
                        Result :=
                          Result
                          & SU.To_Unbounded_String
                              (Tuple_Field_Name (Positive (Index))
                               & " => "
                               & (if Has_Target
                                  then Render_Expr_For_Target_Type
                                    (Unit,
                                     Document,
                                     Expr.Elements (Index),
                                     Target_Info,
                                     State)
                                  else Render_Expr
                                    (Unit,
                                     Document,
                                     Expr.Elements (Index),
                                     State)));
                        First_Association := False;
                     end;
                  end loop;
               end if;
            end;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Annotated =>
            declare
               Target_Name     : constant String := Root_Name (Expr.Target);
               Is_Array_Target : constant Boolean :=
                 Target_Name'Length > 0
                 and then Has_Type (Unit, Document, Target_Name)
                 and then Is_Array_Type
                   (Unit,
                    Document,
                    Lookup_Type (Unit, Document, Target_Name));
            begin
               if Expr.Inner /= null
                 and then Expr.Inner.Kind = CM.Expr_Tuple
                 and then Is_Array_Target
               then
                  return
                    Render_Expr (Unit, Document, Expr.Target, State)
                    & "'"
                    & Render_Positional_Tuple_Aggregate
                        (Unit, Document, Expr.Inner, State);
               end if;
            end;
            return
              Render_Expr (Unit, Document, Expr.Target, State)
              & "'"
              & (if Expr.Inner /= null and then Expr.Inner.Kind = CM.Expr_Aggregate
                 then Render_Expr (Unit, Document, Expr.Inner, State)
                 else "(" & Render_Expr (Unit, Document, Expr.Inner, State) & ")");
         when CM.Expr_Unary =>
            if FT.To_String (Expr.Operator) = "not"
              and then Has_Text (Expr.Type_Name)
              and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Type_Name))
            then
               return
                 Render_Binary_Unary_Image
                   (Unit,
                    Document,
                    Expr,
                    Render_Expr (Unit, Document, Expr.Inner, State));
            end if;
            return
              "("
              & Map_Operator (FT.To_String (Expr.Operator))
              & (if FT.To_String (Expr.Operator) = "not" then " " else "")
              & Render_Expr (Unit, Document, Expr.Inner, State)
              & ")";
         when CM.Expr_Binary =>
            if Has_Text (Expr.Type_Name)
              and then Is_Float_Type (Unit, Document, FT.To_String (Expr.Type_Name))
            then
               declare
                  Convex_Image : constant String :=
                    Render_Float_Convex_Combination (Unit, Document, Expr, State);
               begin
                  if Convex_Image'Length > 0 then
                     return Convex_Image;
                  end if;
               end;
            end if;
            declare
               Left_Type  : GM.Type_Descriptor := (others => <>);
               Right_Type : GM.Type_Descriptor := (others => <>);
               Has_Left_Type  : constant Boolean :=
                 Expr.Left /= null
                 and then Resolve_Print_Type (Unit, Document, Expr.Left, State, Left_Type);
               Has_Right_Type : constant Boolean :=
                 Expr.Right /= null
                 and then Resolve_Print_Type (Unit, Document, Expr.Right, State, Right_Type);
            begin
               if Expr.Left /= null
                 and then Expr.Right /= null
                 and then Has_Left_Type
                 and then Has_Right_Type
                 and then FT.Lowercase (FT.To_String (Left_Type.Kind)) = "string"
                 and then FT.Lowercase (FT.To_String (Right_Type.Kind)) = "string"
               then
                  declare
                     Left_Image : constant String :=
                       Render_String_Expr (Unit, Document, Expr.Left, State);
                     Right_Image : constant String :=
                       Render_String_Expr (Unit, Document, Expr.Right, State);
                     Operator : constant String := FT.To_String (Expr.Operator);
                  begin
                     if Operator = "==" or else Operator = "!=" then
                        return
                          "("
                          & Left_Image
                          & " "
                          & Map_Operator (Operator)
                          & " "
                          & Right_Image
                          & ")";
                     elsif Operator in "<" | "<=" | ">" | ">=" then
                        return
                          "("
                          & Left_Image
                          & " "
                          & Map_Operator (Operator)
                          & " "
                          & Right_Image
                          & ")";
                     elsif Operator = "&" then
                        return "(" & Left_Image & " & " & Right_Image & ")";
                     end if;
                  end;
               end if;
            end;
            if Expr.Left /= null
              and then Has_Text (Expr.Left.Type_Name)
              and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Left.Type_Name))
            then
               return
                 Render_Binary_Operation_Image
                   (Unit,
                    Document,
                    Expr,
                    Render_Expr (Unit, Document, Expr.Left, State),
                    Render_Expr (Unit, Document, Expr.Right, State));
            end if;
            return
              "("
              & Render_Expr (Unit, Document, Expr.Left, State)
              & " "
              & Map_Operator (FT.To_String (Expr.Operator))
              & " "
              & Render_Expr (Unit, Document, Expr.Right, State)
              & ")";
         when CM.Expr_Subtype_Indication =>
            if Has_Text (Expr.Type_Name) then
               return Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name));
            end if;
            Raise_Unsupported
              (State,
               Expr.Span,
               "subtype indication missing type name");
         when others =>
               Raise_Unsupported
                 (State,
                  Expr.Span,
                  "PR09 emitter does not yet support expression kind '"
                  & Expr.Kind'Image
                  & "'");
      end case;
   end Render_Expr;

   function Render_Print_Argument
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Value_Image : constant String := Render_Expr (Unit, Document, Expr, State);
      Info        : GM.Type_Descriptor;
   begin
      if Expr.Kind = CM.Expr_String then
         return Value_Image;
      elsif Expr.Kind = CM.Expr_Bool then
         return "(if " & Value_Image & " then ""true"" else ""false"")";
      elsif Expr.Kind = CM.Expr_Int then
         return
           "Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Long_Long_Integer ("
           & Value_Image
           & ")), Ada.Strings.Both)";
      elsif Resolve_Print_Type (Unit, Document, Expr, State, Info) then
         declare
            Base_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
            Base_Kind : constant String := FT.Lowercase (FT.To_String (Base_Info.Kind));
            Base_Name : constant String := FT.Lowercase (FT.To_String (Base_Info.Name));
         begin
            if Base_Kind = "string" or else Base_Name = "string" then
               if Is_Plain_String_Type (Unit, Document, Info) then
                  State.Needs_Safe_String_RT := True;
                  return
                    "Safe_String_RT.To_String ("
                    & Render_Heap_String_Expr (Unit, Document, Expr, State)
                    & ")";
               end if;
               return Value_Image;
            elsif Base_Kind = "boolean" or else Base_Name = "boolean" then
               return "(if " & Value_Image & " then ""true"" else ""false"")";
            elsif Is_Integer_Type (Unit, Document, Info) then
               return
                 "Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Long_Long_Integer ("
                 & Value_Image
                 & ")), Ada.Strings.Both)";
            end if;
         end;
      end if;

      Raise_Unsupported
        (State,
         Expr.Span,
         "print argument type was not resolved during Ada emission");
   end Render_Print_Argument;

   function Render_Float_Convex_Combination
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      function Is_Real_One (Item : CM.Expr_Access) return Boolean is
      begin
         return
           Item /= null
           and then Item.Kind = CM.Expr_Real
           and then Has_Text (Item.Text)
           and then FT.To_String (Item.Text) = "1.0";
      end Is_Real_One;

      function Images_Match (Left, Right : CM.Expr_Access) return Boolean is
      begin
         return Left /= null
           and then Right /= null
           and then Render_Expr (Unit, Document, Left, State) = Render_Expr (Unit, Document, Right, State);
      end Images_Match;

      function Complement_Of
        (Candidate, Weight : CM.Expr_Access) return Boolean is
      begin
         return
           Candidate /= null
           and then Candidate.Kind = CM.Expr_Binary
           and then FT.To_String (Candidate.Operator) = "-"
           and then Is_Real_One (Candidate.Left)
           and then Images_Match (Candidate.Right, Weight);
      end Complement_Of;

      function Extract_Product
        (Term      : CM.Expr_Access;
         Weight    : out CM.Expr_Access;
         Component : out CM.Expr_Access) return Boolean
      is
      begin
         if Term = null or else Term.Kind /= CM.Expr_Binary or else FT.To_String (Term.Operator) /= "*" then
            Weight := null;
            Component := null;
            return False;
         end if;

         Weight := Term.Left;
         Component := Term.Right;
         return True;
      end Extract_Product;

      W1, W2 : CM.Expr_Access := null;
      V1, V2 : CM.Expr_Access := null;
   begin
      if Expr = null
        or else Expr.Kind /= CM.Expr_Binary
        or else FT.To_String (Expr.Operator) /= "+"
      then
         return "";
      end if;

      if not Extract_Product (Expr.Left, W1, V1)
        or else not Extract_Product (Expr.Right, W2, V2)
      then
         return "";
      end if;

      if Complement_Of (W1, W2) then
         return
           "("
           & Render_Expr (Unit, Document, V1, State)
           & " + ("
           & Render_Expr (Unit, Document, W2, State)
           & " * ("
           & Render_Expr (Unit, Document, V2, State)
           & " - "
           & Render_Expr (Unit, Document, V1, State)
           & ")))";
      elsif Complement_Of (W2, W1) then
         return
           "("
           & Render_Expr (Unit, Document, V2, State)
           & " + ("
           & Render_Expr (Unit, Document, W1, State)
           & " * ("
           & Render_Expr (Unit, Document, V1, State)
           & " - "
           & Render_Expr (Unit, Document, V2, State)
           & ")))";
      end if;

      return "";
   end Render_Float_Convex_Combination;

   function Uses_Wide_Value
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Expr     : CM.Expr_Access) return Boolean
   is
   begin
      pragma Unreferenced (Unit, Document, State, Expr);
      return False;
   end Uses_Wide_Value;

   function Is_Explicit_Float_Narrowing
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Type : String;
      Expr        : CM.Expr_Access) return Boolean
   is
   begin
      return Target_Type'Length > 0
        and then Is_Float_Type (Unit, Document, Target_Type)
        and then not Is_Builtin_Float_Name (Target_Type)
        and then Expr /= null
        and then Expr.Kind = CM.Expr_Conversion
        and then Expr.Inner /= null
        and then Has_Text (Expr.Type_Name)
        and then FT.To_String (Expr.Type_Name) = Target_Type;
   end Is_Explicit_Float_Narrowing;

   function Try_Render_Stable_Float_Interpolation
     (Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Expr            : CM.Expr_Access;
      State           : in out Emit_State;
      Condition_Image : out FT.UString;
      Lower_Image     : out FT.UString;
      Upper_Image     : out FT.UString) return Boolean
   is
      function Is_Real_One (Item : CM.Expr_Access) return Boolean is
      begin
         return
           Item /= null
           and then Item.Kind = CM.Expr_Real
           and then Has_Text (Item.Text)
           and then FT.To_String (Item.Text) = "1.0";
      end Is_Real_One;

      function Images_Match (Left, Right : CM.Expr_Access) return Boolean is
      begin
         return Left /= null
           and then Right /= null
           and then Render_Expr (Unit, Document, Left, State) = Render_Expr (Unit, Document, Right, State);
      end Images_Match;

      function Complement_Of
        (Candidate, Weight : CM.Expr_Access) return Boolean is
      begin
         return
           Candidate /= null
           and then Candidate.Kind = CM.Expr_Binary
           and then FT.To_String (Candidate.Operator) = "-"
           and then Is_Real_One (Candidate.Left)
           and then Images_Match (Candidate.Right, Weight);
      end Complement_Of;

      function Extract_Product
        (Term      : CM.Expr_Access;
         Weight    : out CM.Expr_Access;
         Component : out CM.Expr_Access) return Boolean
      is
      begin
         if Term = null or else Term.Kind /= CM.Expr_Binary or else FT.To_String (Term.Operator) /= "*" then
            Weight := null;
            Component := null;
            return False;
         end if;

         Weight := Term.Left;
         Component := Term.Right;
         return True;
      end Extract_Product;

      function Match_Delta_Form
        (Candidate : CM.Expr_Access;
         Anchor    : out CM.Expr_Access;
         Other     : out CM.Expr_Access;
         Weight    : out CM.Expr_Access) return Boolean
      is
         Delta_Term : CM.Expr_Access := null;
      begin
         if Candidate = null
           or else Candidate.Kind /= CM.Expr_Binary
           or else FT.To_String (Candidate.Operator) /= "+"
         then
            Anchor := null;
            Other := null;
            Weight := null;
            return False;
         end if;

         if Extract_Product (Candidate.Right, Weight, Delta_Term)
           and then Delta_Term /= null
           and then Delta_Term.Kind = CM.Expr_Binary
           and then FT.To_String (Delta_Term.Operator) = "-"
           and then Images_Match (Candidate.Left, Delta_Term.Right)
         then
            Anchor := Candidate.Left;
            Other := Delta_Term.Left;
            return True;
         elsif Extract_Product (Candidate.Left, Weight, Delta_Term)
           and then Delta_Term /= null
           and then Delta_Term.Kind = CM.Expr_Binary
           and then FT.To_String (Delta_Term.Operator) = "-"
           and then Images_Match (Candidate.Right, Delta_Term.Right)
         then
            Anchor := Candidate.Right;
            Other := Delta_Term.Left;
            return True;
         end if;

         Anchor := null;
         Other := null;
         Weight := null;
         return False;
      end Match_Delta_Form;

      Weight_1     : CM.Expr_Access := null;
      Weight_2     : CM.Expr_Access := null;
      Value_1      : CM.Expr_Access := null;
      Value_2      : CM.Expr_Access := null;
      Anchor       : CM.Expr_Access := null;
      Other        : CM.Expr_Access := null;
      Weight       : CM.Expr_Access := null;
      Anchor_Image : FT.UString := FT.To_UString ("");
      Other_Image  : FT.UString := FT.To_UString ("");
      Weight_Image : FT.UString := FT.To_UString ("");
   begin
      Condition_Image := FT.To_UString ("");
      Lower_Image := FT.To_UString ("");
      Upper_Image := FT.To_UString ("");

      if Match_Delta_Form (Expr, Anchor, Other, Weight) then
         null;
      elsif Expr /= null
        and then Expr.Kind = CM.Expr_Binary
        and then FT.To_String (Expr.Operator) = "+"
        and then Extract_Product (Expr.Left, Weight_1, Value_1)
        and then Extract_Product (Expr.Right, Weight_2, Value_2)
      then
         if Complement_Of (Weight_1, Weight_2) then
            Anchor := Value_1;
            Other := Value_2;
            Weight := Weight_2;
         elsif Complement_Of (Weight_2, Weight_1) then
            Anchor := Value_2;
            Other := Value_1;
            Weight := Weight_1;
         else
            return False;
         end if;
      else
         return False;
      end if;

      if Anchor = null or else Other = null or else Weight = null then
         return False;
      end if;

      Anchor_Image := FT.To_UString (Render_Expr (Unit, Document, Anchor, State));
      Other_Image := FT.To_UString (Render_Expr (Unit, Document, Other, State));
      Weight_Image := FT.To_UString (Render_Expr (Unit, Document, Weight, State));

      Condition_Image := FT.To_UString (FT.To_String (Weight_Image) & " <= 0.5");
      Lower_Image :=
        FT.To_UString
          ("("
           & FT.To_String (Anchor_Image)
           & " + ("
           & FT.To_String (Weight_Image)
           & " * ("
           & FT.To_String (Other_Image)
           & " - "
           & FT.To_String (Anchor_Image)
           & ")))");
      Upper_Image :=
        FT.To_UString
          ("("
           & FT.To_String (Other_Image)
           & " - ((1.0 - "
           & FT.To_String (Weight_Image)
           & ") * ("
           & FT.To_String (Other_Image)
           & " - "
           & FT.To_String (Anchor_Image)
           & ")))");
      return True;
   end Try_Render_Stable_Float_Interpolation;

   function Render_Channel_Send_Value
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Expr : CM.Expr_Access;
      Value        : CM.Expr_Access) return String
   is
      Channel_Name : constant String :=
        (if Channel_Expr = null then "" else CM.Flatten_Name (Channel_Expr));
      Channel_Item : constant CM.Resolved_Channel_Decl :=
        Lookup_Channel (Unit, Channel_Name);
   begin
      if Has_Text (Channel_Item.Name)
        and then Is_Integer_Type (Unit, Document, Channel_Item.Element_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         return
           Render_Type_Name (Channel_Item.Element_Type)
           & " ("
           & Render_Wide_Expr (Unit, Document, Value, State)
           & ")";
      end if;
      return Render_Expr (Unit, Document, Value, State);
   end Render_Channel_Send_Value;

   procedure Collect_Wide_Locals_From_Statements
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Local_Names : FT.UString_Vectors.Vector;
      Statements  : CM.Statement_Access_Vectors.Vector);

   procedure Collect_Local_Names
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector;
      Names        : in out FT.UString_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         for Name of Decl.Names loop
            if not Contains_Name (Names, FT.To_String (Name)) then
               Names.Append (Name);
            end if;
         end loop;
      end loop;
      for Item of Statements loop
         if Item /= null and then Item.Kind in CM.Stmt_Object_Decl | CM.Stmt_Destructure_Decl then
            declare
               Decl_Names : constant FT.UString_Vectors.Vector :=
                 (if Item.Kind = CM.Stmt_Object_Decl
                  then Item.Decl.Names
                  else Item.Destructure.Names);
            begin
               for Name of Decl_Names loop
                  if not Contains_Name (Names, FT.To_String (Name)) then
                     Names.Append (Name);
                  end if;
               end loop;
            end;
         end if;
      end loop;
   end Collect_Local_Names;

   procedure Collect_Local_Names
     (Declarations : CM.Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector;
      Names        : in out FT.UString_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         for Name of Decl.Names loop
            if not Contains_Name (Names, FT.To_String (Name)) then
               Names.Append (Name);
            end if;
         end loop;
      end loop;
      for Item of Statements loop
         if Item /= null and then Item.Kind in CM.Stmt_Object_Decl | CM.Stmt_Destructure_Decl then
            declare
               Decl_Names : constant FT.UString_Vectors.Vector :=
                 (if Item.Kind = CM.Stmt_Object_Decl
                  then Item.Decl.Names
                  else Item.Destructure.Names);
            begin
               for Name of Decl_Names loop
                  if not Contains_Name (Names, FT.To_String (Name)) then
                     Names.Append (Name);
                  end if;
               end loop;
            end;
         end if;
      end loop;
   end Collect_Local_Names;

   procedure Mark_Wide_Declaration
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      State     : in out Emit_State;
      Decl      : CM.Resolved_Object_Decl) is
   begin
      if Is_Integer_Type (Unit, Document, Decl.Type_Info)
        and then Decl.Has_Initializer
        and then Uses_Wide_Value (Unit, Document, State, Decl.Initializer)
      then
         for Name of Decl.Names loop
            Add_Wide_Name (State, FT.To_String (Name));
         end loop;
      end if;
   end Mark_Wide_Declaration;

   procedure Mark_Wide_Declaration
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      State     : in out Emit_State;
      Decl      : CM.Object_Decl) is
   begin
      if Is_Integer_Type (Unit, Document, Decl.Type_Info)
        and then Decl.Has_Initializer
        and then Uses_Wide_Value (Unit, Document, State, Decl.Initializer)
      then
         for Name of Decl.Names loop
            Add_Wide_Name (State, FT.To_String (Name));
         end loop;
      end if;
   end Mark_Wide_Declaration;

   procedure Collect_Wide_Locals_From_Statements
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Local_Names : FT.UString_Vectors.Vector;
      Statements  : CM.Statement_Access_Vectors.Vector) is
   begin
      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Object_Decl =>
                  Mark_Wide_Declaration (Unit, Document, State, Item.Decl);
               when CM.Stmt_Destructure_Decl =>
                  null;
               when CM.Stmt_Assign =>
                  if Item.Target /= null
                    and then Item.Target.Kind = CM.Expr_Ident
                    and then Contains_Name (Local_Names, FT.To_String (Item.Target.Name))
                    and then Uses_Wide_Value (Unit, Document, State, Item.Value)
                    and then Expr_Uses_Name (Item.Value, FT.To_String (Item.Target.Name))
                  then
                     Add_Wide_Name (State, FT.To_String (Item.Target.Name));
                  end if;
               when CM.Stmt_If =>
                  Collect_Wide_Locals_From_Statements
                    (Unit, Document, State, Local_Names, Item.Then_Stmts);
                  for Part of Item.Elsifs loop
                     Collect_Wide_Locals_From_Statements
                       (Unit, Document, State, Local_Names, Part.Statements);
                  end loop;
                  if Item.Has_Else then
                     Collect_Wide_Locals_From_Statements
                       (Unit, Document, State, Local_Names, Item.Else_Stmts);
                  end if;
               when CM.Stmt_Case =>
                  for Arm of Item.Case_Arms loop
                     Collect_Wide_Locals_From_Statements
                       (Unit, Document, State, Local_Names, Arm.Statements);
                  end loop;
               when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                  Collect_Wide_Locals_From_Statements
                    (Unit, Document, State, Local_Names, Item.Body_Stmts);
               when CM.Stmt_Select =>
                  for Arm of Item.Arms loop
                     case Arm.Kind is
                        when CM.Select_Arm_Channel =>
                           Collect_Wide_Locals_From_Statements
                             (Unit, Document, State, Local_Names, Arm.Channel_Data.Statements);
                        when CM.Select_Arm_Delay =>
                           Collect_Wide_Locals_From_Statements
                             (Unit, Document, State, Local_Names, Arm.Delay_Data.Statements);
                        when others =>
                           null;
                     end case;
                  end loop;
               when others =>
                  null;
            end case;
         end if;
      end loop;
   end Collect_Wide_Locals_From_Statements;

   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector) is
      Local_Names : FT.UString_Vectors.Vector;
   begin
      Collect_Local_Names (Declarations, Statements, Local_Names);
      for Decl of Declarations loop
         Mark_Wide_Declaration (Unit, Document, State, Decl);
      end loop;
      Collect_Wide_Locals_From_Statements
        (Unit, Document, State, Local_Names, Statements);
   end Collect_Wide_Locals;

   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector) is
      Local_Names : FT.UString_Vectors.Vector;
   begin
      Collect_Local_Names (Declarations, Statements, Local_Names);
      for Decl of Declarations loop
         Mark_Wide_Declaration (Unit, Document, State, Decl);
      end loop;
      Collect_Wide_Locals_From_Statements
        (Unit, Document, State, Local_Names, Statements);
   end Collect_Wide_Locals;

   function Render_Wide_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Operator : constant String :=
        (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
   begin
      State.Needs_Safe_Runtime := True;

      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null wide expression during Ada emission");
      end if;

      case Expr.Kind is
         when CM.Expr_Int =>
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
         when CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index | CM.Expr_Call =>
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
         when CM.Expr_Conversion =>
            if Has_Text (Expr.Type_Name)
              and then Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name))
              and then Expr.Inner /= null
            then
               return Render_Wide_Expr (Unit, Document, Expr.Inner, State);
            end if;
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
         when CM.Expr_Unary =>
            return "(" & Operator & Render_Wide_Expr (Unit, Document, Expr.Inner, State) & ")";
         when CM.Expr_Binary =>
            if Operator in "+" | "-" | "*" | "/" | "mod" | "rem" then
               return
                 "("
                 & Render_Wide_Expr (Unit, Document, Expr.Left, State)
                 & " "
                 & Operator
                 & " "
                 & Render_Wide_Expr (Unit, Document, Expr.Right, State)
                 & ")";
            end if;
            return "Safe_Runtime.Wide_Integer (Boolean'Pos" & Render_Expr (Unit, Document, Expr, State) & ")";
         when others =>
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
      end case;
   end Render_Wide_Expr;

   function Render_Wide_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String
   is
      Operator : constant String :=
        (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
   begin
      State.Needs_Safe_Runtime := True;

      if not Supported then
         return "";
      elsif Expr = null or else Target = null then
         Supported := False;
         return "";
      elsif Exprs_Match (Expr, Target) then
         return "Safe_Runtime.Wide_Integer (" & Replacement & ")";
      end if;

      case Expr.Kind is
         when CM.Expr_Int =>
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index | CM.Expr_Call =>
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Conversion =>
            if Has_Text (Expr.Type_Name)
              and then Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name))
              and then Expr.Inner /= null
            then
               return
                 Render_Wide_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Inner, Target, Replacement, State, Supported);
            end if;
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Unary =>
            return
              "("
              & Operator
              & Render_Wide_Expr_With_Target_Substitution
                  (Unit, Document, Expr.Inner, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Binary =>
            if Operator in "+" | "-" | "*" | "/" | "mod" | "rem" then
               return
                 "("
                 & Render_Wide_Expr_With_Target_Substitution
                     (Unit, Document, Expr.Left, Target, Replacement, State, Supported)
                 & " "
                 & Operator
                 & " "
                 & Render_Wide_Expr_With_Target_Substitution
                     (Unit, Document, Expr.Right, Target, Replacement, State, Supported)
                 & ")";
            end if;
            return
              "Safe_Runtime.Wide_Integer (Boolean'Pos"
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when others =>
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
      end case;
   end Render_Wide_Expr_With_Target_Substitution;

   function Render_Object_Decl_Text_Common
     (Unit           : CM.Resolved_Unit;
      Document       : GM.Mir_Document;
      State          : in out Emit_State;
      Names          : FT.UString_Vectors.Vector;
      Type_Info      : GM.Type_Descriptor;
      Is_Constant    : Boolean;
      Has_Initializer : Boolean;
      Has_Implicit_Default_Init : Boolean;
      Initializer    : CM.Expr_Access;
      Local_Context  : Boolean := False) return String
   is
      Result : SU.Unbounded_String;
      Constant_Qualifier : constant String :=
        (if Is_Constant and then not Is_Owner_Access (Type_Info) then "constant " else "");
      Type_Name : constant String :=
        (if Is_Integer_Type (Unit, Document, Type_Info)
           and then Names_Use_Wide_Storage (State, Names)
         then "safe_runtime.wide_integer"
         elsif Local_Context
           and then Is_Access_Type (Type_Info)
           and then not Is_Owner_Access (Type_Info)
           and then Has_Text (Type_Info.Target)
         then
           (if Type_Info.Not_Null then "not null " else "")
           & "access "
           & (if Type_Info.Is_Constant then "constant " else "")
           & FT.To_String (Type_Info.Target)
         elsif Is_Owner_Access (Type_Info)
         then Render_Type_Name (Type_Info)
         else Render_Subtype_Indication (Unit, Document, Type_Info));
      function Render_Initializer return String is
      begin
         if Initializer /= null and then Is_Owner_Access (Type_Info) then
            return
              Render_Expr_For_Target_Type
                (Unit, Document, Initializer, Type_Info, State);
         elsif Initializer /= null and then Is_Bounded_String_Type (Type_Info) then
            return
              Render_Expr_For_Target_Type
                (Unit, Document, Initializer, Type_Info, State);
         end if;
         if Initializer /= null
           and then Initializer.Kind = CM.Expr_Aggregate
           and then not Type_Info.Discriminant_Constraints.Is_Empty
           and then Type_Name /= "safe_runtime.wide_integer"
         then
            return
              Type_Name
              & "'"
              & Render_Record_Aggregate_For_Type
                 (Unit, Document, Initializer, Type_Info, State);
         elsif Initializer /= null
           and then Initializer.Kind = CM.Expr_Tuple
           and then Is_Array_Type (Unit, Document, Type_Info)
           and then Type_Name /= "safe_runtime.wide_integer"
         then
            return
              Type_Name
              & "'"
              & Render_Positional_Tuple_Aggregate
                  (Unit, Document, Initializer, State);
         elsif Initializer /= null
           and then Initializer.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
           and then Type_Name /= "safe_runtime.wide_integer"
         then
            return Type_Name & "'" & Render_Expr (Unit, Document, Initializer, State);
         end if;
         return Render_Expr_For_Target_Type (Unit, Document, Initializer, Type_Info, State);
      end Render_Initializer;
      Defer_Heap_Init : constant Boolean :=
        not Local_Context
        and then Has_Initializer
        and then not Is_Constant
        and then Has_Heap_Value_Type (Unit, Document, Type_Info);
   begin
      if Type_Name = "safe_runtime.wide_integer" then
         State.Needs_Safe_Runtime := True;
      end if;
      for Index in Names.First_Index .. Names.Last_Index loop
         if Index /= Names.First_Index then
            Result := Result & SU.To_Unbounded_String ("; ");
         end if;
         Result :=
           Result
           & SU.To_Unbounded_String
                (FT.To_String (Names (Index))
                & " : "
                & Constant_Qualifier
                & Type_Name);
         if Has_Initializer or else Has_Implicit_Default_Init then
            if Type_Name = "safe_runtime.wide_integer" then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Render_Wide_Expr (Unit, Document, Initializer, State));
            elsif Defer_Heap_Init then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Default_Value_Expr (Unit, Document, Type_Info));
            elsif Has_Implicit_Default_Init and then Initializer = null then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Default_Value_Expr (Type_Info));
            elsif Is_Integer_Type (Unit, Document, Type_Info)
              and then Uses_Wide_Value (Unit, Document, State, Initializer)
            then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := "
                      & Render_Type_Name (Type_Info)
                      & " ("
                      & Render_Wide_Expr (Unit, Document, Initializer, State)
                      & ")");
            else
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Render_Initializer);
            end if;
         end if;
      end loop;
      return SU.To_String (Result) & ";";
   end Render_Object_Decl_Text_Common;

   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Resolved_Object_Decl;
      Local_Context : Boolean := False) return String
   is
   begin
      return
        Render_Object_Decl_Text_Common
          (Unit            => Unit,
           Document        => Document,
           State           => State,
           Names           => Decl.Names,
           Type_Info       => Decl.Type_Info,
           Is_Constant     => Decl.Is_Constant,
           Has_Initializer => Decl.Has_Initializer,
           Has_Implicit_Default_Init => Decl.Has_Implicit_Default_Init,
           Initializer     => Decl.Initializer,
           Local_Context   => Local_Context);
   end Render_Object_Decl_Text;

   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Object_Decl;
      Local_Context : Boolean := False) return String
   is
   begin
      return
        Render_Object_Decl_Text_Common
          (Unit            => Unit,
           Document        => Document,
           State           => State,
           Names           => Decl.Names,
           Type_Info       => Decl.Type_Info,
           Is_Constant     => Decl.Is_Constant,
           Has_Initializer => Decl.Has_Initializer,
           Has_Implicit_Default_Init => Decl.Has_Implicit_Default_Init,
           Initializer     => Decl.Initializer,
           Local_Context   => Local_Context);
   end Render_Object_Decl_Text;

   function Render_Subprogram_Params
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Params     : CM.Symbol_Vectors.Vector) return String
   is
      Result : SU.Unbounded_String := SU.To_Unbounded_String ("(");
   begin
      if Params.Is_Empty then
         return "";
      end if;

      for Index in Params.First_Index .. Params.Last_Index loop
         declare
            Param : constant CM.Symbol := Params (Index);
            Mode  : constant String := FT.To_String (Param.Mode);
         begin
            if Index /= Params.First_Index then
               Result := Result & SU.To_Unbounded_String ("; ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Param.Name)
                   & " : "
                  & (if Mode = "" or else Mode = "borrow"
                      then "in "
                      elsif Mode = "mut"
                      then "in out "
                      elsif Mode = "in"
                      then "in "
                      else Mode & " ")
                   & Render_Param_Type_Name (Unit, Document, Param.Type_Info));
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Subprogram_Params;

   function Render_Subprogram_Return
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram) return String is
   begin
      if Subprogram.Has_Return_Type then
         return
           " return "
           & Render_Subtype_Indication (Unit, Document, Subprogram.Return_Type);
      end if;
      return "";
   end Render_Subprogram_Return;

   function Render_Ada_Subprogram_Keyword
     (Subprogram : CM.Resolved_Subprogram) return String is
   begin
      if Subprogram.Has_Return_Type then
         return "function";
      end if;
      return "procedure";
   end Render_Ada_Subprogram_Keyword;

   function Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl of Declarations loop
         if Is_Alias_Access (Decl.Type_Info) then
            Result.Append (Decl);
         end if;
      end loop;
      return Result;
   end Alias_Declarations;

   function Non_Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl of Declarations loop
         if not Is_Alias_Access (Decl.Type_Info) then
            Result.Append (Decl);
         end if;
      end loop;
      return Result;
   end Non_Alias_Declarations;

   procedure Render_In_Out_Param_Stabilizers
     (Buffer     : in out SU.Unbounded_String;
      Subprogram : CM.Resolved_Subprogram;
      Depth      : Natural)
   is
   begin
      for Param of Subprogram.Params loop
         if FT.To_String (Param.Mode) in "mut" | "in out"
           and then Is_Owner_Access (Param.Type_Info)
         then
            declare
               Param_Name    : constant String := FT.To_String (Param.Name);
               Snapshot_Name : constant String := Param_Name & "_Snapshot";
            begin
               Append_Line (Buffer, "declare", Depth);
               Append_Line
                 (Buffer,
                  Snapshot_Name
                  & " : constant "
                  & Render_Type_Name (Param.Type_Info)
                  & " := "
                  & Param_Name
                  & ";",
                  Depth + 1);
               Append_Line (Buffer, "begin", Depth);
               Append_Line (Buffer, Param_Name & " := " & Snapshot_Name & ";", Depth + 1);
               Append_Line (Buffer, "end;", Depth);
            end;
         end if;
      end loop;
   end Render_In_Out_Param_Stabilizers;

   function Find_Graph_Summary
     (Bronze : MB.Bronze_Result;
      Name   : String) return MB.Graph_Summary
   is
   begin
      for Item of Bronze.Graphs loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Find_Graph_Summary;

   function Render_Initializes_Aspect
     (Unit   : CM.Resolved_Unit;
      Bronze : MB.Bronze_Result) return String
   is
      Items : FT.UString_Vectors.Vector;

      procedure Add_Unique (Name : String) is
      begin
         if Name'Length > 0 and then not Contains_Name (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;
   begin
      for Item of Bronze.Initializes loop
         if Is_Aspect_State_Name (FT.To_String (Item))
           and then not Is_Constant_Object_Name (Unit, FT.To_String (Item))
         then
            Add_Unique (FT.To_String (Item));
         end if;
      end loop;

      for Channel of Unit.Channels loop
         Add_Unique (FT.To_String (Channel.Name));
      end loop;

      for Task_Item of Unit.Tasks loop
         Add_Unique (FT.To_String (Task_Item.Name));
      end loop;

      if Items.Is_Empty then
         return "null";
      elsif Items.Length = 1 then
         return FT.To_String (Items (Items.First_Index));
      end if;
      return "(" & Join_Names (Items) & ")";
   end Render_Initializes_Aspect;

   function Render_Global_Aspect
     (Unit    : CM.Resolved_Unit;
      Summary : MB.Graph_Summary) return String
   is
      Inputs  : FT.UString_Vectors.Vector;
      Outputs : FT.UString_Vectors.Vector;
      In_Outs : FT.UString_Vectors.Vector;

      function Contains
        (Items : FT.UString_Vectors.Vector;
         Name  : String) return Boolean is
      begin
         for Item of Items loop
            if FT.To_String (Item) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      procedure Add_Unique
        (Items : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if not Contains (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;

      Result : SU.Unbounded_String := SU.To_Unbounded_String ("");
      First  : Boolean := True;
   begin
      for Item of Summary.Reads loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              or else FT.To_String (Item) = "return"
              or else not Is_Aspect_State_Name (Name)
              or else Is_Constant_Object_Name (Unit, Name)
            then
               null;
            elsif Contains (Summary.Writes, FT.To_String (Item)) then
               Add_Unique (In_Outs, Name);
            else
               Add_Unique (Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Writes loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              or else FT.To_String (Item) = "return"
              or else not Is_Aspect_State_Name (Name)
              or else Is_Constant_Object_Name (Unit, Name)
            then
               null;
            elsif not Contains (Summary.Reads, FT.To_String (Item)) then
               Add_Unique (Outputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Channels loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Is_Aspect_State_Name (Name) then
               Add_Unique (In_Outs, Name);
            end if;
         end;
      end loop;

      if Inputs.Is_Empty and then Outputs.Is_Empty and then In_Outs.Is_Empty then
         return "null";
      end if;

      if not Inputs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "Input => "
                & (if Inputs.Length = 1
                   then FT.To_String (Inputs (Inputs.First_Index))
                   else "(" & Join_Names (Inputs) & ")"));
         First := False;
      end if;

      if not Outputs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "Output => "
                & (if Outputs.Length = 1
                   then FT.To_String (Outputs (Outputs.First_Index))
                   else "(" & Join_Names (Outputs) & ")"));
         First := False;
      end if;

      if not In_Outs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "In_Out => "
                & (if In_Outs.Length = 1
                   then FT.To_String (In_Outs (In_Outs.First_Index))
                   else "(" & Join_Names (In_Outs) & ")"));
      end if;

      return "(" & SU.To_String (Result) & ")";
   end Render_Global_Aspect;

   function Render_Depends_Aspect
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Summary    : MB.Graph_Summary) return String
   is
      Result : SU.Unbounded_String;
      Allowed_Outputs : FT.UString_Vectors.Vector;
      Allowed_Inputs  : FT.UString_Vectors.Vector;
      Formal_Input_Params : FT.UString_Vectors.Vector;
      Read_Param_Inputs : FT.UString_Vectors.Vector;

      function Contains
        (Items : FT.UString_Vectors.Vector;
         Name  : String) return Boolean is
      begin
         for Item of Items loop
            if FT.To_String (Item) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      procedure Add_Unique
        (Items : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if not Contains (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;
   begin
      for Param of Subprogram.Params loop
         declare
            Name : constant String := FT.To_String (Param.Name);
            Mode : constant String := FT.To_String (Param.Mode);
         begin
            if Mode = "mut" then
               Add_Unique (Allowed_Outputs, Name);
               Add_Unique (Allowed_Inputs, Name);
               Add_Unique (Formal_Input_Params, Name);
            elsif Mode = "out" then
               Add_Unique (Allowed_Outputs, Name);
            elsif Mode = "in out" then
               Add_Unique (Allowed_Outputs, Name);
               Add_Unique (Allowed_Inputs, Name);
               Add_Unique (Formal_Input_Params, Name);
            else
               Add_Unique (Allowed_Inputs, Name);
               Add_Unique (Formal_Input_Params, Name);
            end if;
         end;
      end loop;

      if Subprogram.Has_Return_Type then
         Add_Unique
           (Allowed_Outputs,
            FT.To_String (Subprogram.Name) & "'Result");
      end if;

      for Item of Summary.Reads loop
         declare
            Name : constant String :=
              Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Item));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              and then Is_Aspect_State_Name (Name)
            then
               Add_Unique (Read_Param_Inputs, Name);
            end if;
            if not Starts_With (FT.To_String (Item), "param:")
              and then FT.To_String (Item) /= "return"
              and then Is_Aspect_State_Name (Name)
              and then not Is_Constant_Object_Name (Unit, Name)
            then
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Writes loop
         declare
            Name : constant String :=
              Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Item));
         begin
            if not Starts_With (FT.To_String (Item), "param:")
              and then FT.To_String (Item) /= "return"
              and then Is_Aspect_State_Name (Name)
              and then not Is_Constant_Object_Name (Unit, Name)
            then
               Add_Unique (Allowed_Outputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Channels loop
         declare
            Name : constant String :=
              Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Item));
         begin
            if Is_Aspect_State_Name (Name) then
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Depends loop
         declare
            Output_Name : constant String :=
              Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Item.Output_Name));
         begin
            if not Starts_With (FT.To_String (Item.Output_Name), "param:")
              and then FT.To_String (Item.Output_Name) /= "return"
              and then Is_Aspect_State_Name (Output_Name)
              and then not Is_Constant_Object_Name (Unit, Output_Name)
            then
               Add_Unique (Allowed_Outputs, Output_Name);
            end if;
            for Input of Item.Inputs loop
               declare
                  Name : constant String :=
                    Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Input));
               begin
                  if not Starts_With (FT.To_String (Input), "param:")
                    and then FT.To_String (Input) /= "return"
                    and then Is_Aspect_State_Name (Name)
                    and then not Is_Constant_Object_Name (Unit, Name)
                  then
                     Add_Unique (Allowed_Inputs, Name);
                  end if;
               end;
            end loop;
         end;
      end loop;

      if not Summary.Channels.Is_Empty then
         return "";
      end if;

      if Summary.Depends.Is_Empty then
         return "";
      end if;

      for Index in Summary.Depends.First_Index .. Summary.Depends.Last_Index loop
         declare
            Item : constant MB.Depends_Entry := Summary.Depends (Index);
            Output_Name : constant String :=
              Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Item.Output_Name));
         begin
            if not Contains (Allowed_Outputs, Output_Name) then
               Raise_Internal
                 ("invalid Depends output `" & Output_Name
                  & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
            end if;
            if Index /= Summary.Depends.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result := Result & SU.To_Unbounded_String (Output_Name & " => ");
            declare
               Inputs : FT.UString_Vectors.Vector;
            begin
               for Input of Item.Inputs loop
                  declare
                     Name : constant String :=
                       Normalize_Aspect_Name
                         (FT.To_String (Subprogram.Name),
                          FT.To_String (Input));
                  begin
                     if not Is_Aspect_State_Name (Name)
                       or else Is_Constant_Object_Name (Unit, Name)
                     then
                        null;
                     elsif not Contains (Allowed_Inputs, Name) then
                        Raise_Internal
                          ("invalid Depends input `" & Name
                           & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
                     else
                        Add_Unique (Inputs, Name);
                     end if;
                  end;
               end loop;

               for Channel of Summary.Channels loop
                  declare
                     Name : constant String :=
                       Normalize_Aspect_Name
                         (FT.To_String (Subprogram.Name),
                          FT.To_String (Channel));
                  begin
                     if not Is_Aspect_State_Name (Name) then
                        null;
                     elsif not Contains (Allowed_Inputs, Name) then
                        Raise_Internal
                          ("invalid Depends input `" & Name
                           & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
                     else
                        Add_Unique (Inputs, Name);
                     end if;
                  end;
               end loop;

               for Input of Read_Param_Inputs loop
                  if Contains (Allowed_Inputs, FT.To_String (Input)) then
                     Add_Unique (Inputs, FT.To_String (Input));
                  end if;
               end loop;

               for Input of Formal_Input_Params loop
                  if Contains (Allowed_Inputs, FT.To_String (Input)) then
                     Add_Unique (Inputs, FT.To_String (Input));
                  end if;
               end loop;

               if Inputs.Is_Empty then
                  Result := Result & SU.To_Unbounded_String ("null");
               elsif Inputs.Length = 1 then
                  Result :=
                    Result
                    & SU.To_Unbounded_String (FT.To_String (Inputs (Inputs.First_Index)));
               else
                  Result :=
                    Result
                    & SU.To_Unbounded_String ("(" & Join_Names (Inputs) & ")");
               end if;
            end;
         end;
      end loop;

      return SU.To_String (Result);
   end Render_Depends_Aspect;

   function Render_Access_Param_Precondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Conditions : FT.UString_Vectors.Vector;

      function Is_Alias_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then Param.Type_Info.Anonymous
              and then Is_Alias_Access (Param.Type_Info)
            then
               return True;
            end if;
         end loop;
         return False;
      end Is_Alias_Param_Name;

      function Needs_Non_Null_Param_Check (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then Is_Owner_Access (Param.Type_Info)
              and then not Param.Type_Info.Not_Null
            then
               return True;
            end if;
         end loop;
         return False;
      end Needs_Non_Null_Param_Check;

      function Expr_Allows_Null
        (Expr       : CM.Expr_Access;
         Param_Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));

         function Is_Direct_Param_Null_Equality return Boolean is
         begin
            return
              ((Expr.Left /= null
                and then Expr.Left.Kind = CM.Expr_Ident
                and then FT.To_String (Expr.Left.Name) = Param_Name
                and then Expr.Right /= null
                and then Expr.Right.Kind = CM.Expr_Null)
               or else
               (Expr.Right /= null
                and then Expr.Right.Kind = CM.Expr_Ident
                and then FT.To_String (Expr.Right.Name) = Param_Name
                and then Expr.Left /= null
                and then Expr.Left.Kind = CM.Expr_Null));
         end Is_Direct_Param_Null_Equality;
      begin
         if Expr = null then
            return False;
         elsif Expr.Kind = CM.Expr_Binary then
            if Operator = "=" then
               return Is_Direct_Param_Null_Equality;
            elsif Operator in "or" | "or else" then
               return
                 Expr_Allows_Null (Expr.Left, Param_Name)
                 or else Expr_Allows_Null (Expr.Right, Param_Name);
            end if;
         end if;
         return False;
      end Expr_Allows_Null;

      function Has_Leading_Null_Return_Guard (Param_Name : String) return Boolean is
      begin
         if Subprogram.Statements.Is_Empty then
            return False;
         end if;

         declare
            First_Stmt : constant CM.Statement_Access := Subprogram.Statements.First_Element;
         begin
            return
              First_Stmt /= null
              and then First_Stmt.Kind = CM.Stmt_If
              and then not First_Stmt.Then_Stmts.Is_Empty
              and then First_Stmt.Then_Stmts.First_Element /= null
              and then First_Stmt.Then_Stmts.First_Element.Kind = CM.Stmt_Return
              and then Expr_Allows_Null (First_Stmt.Condition, Param_Name);
         end;
      end Has_Leading_Null_Return_Guard;

      procedure Add_Unique (Condition : String) is
      begin
         if Condition'Length > 0 and then not Contains_Name (Conditions, Condition) then
            Conditions.Append (FT.To_UString (Condition));
         end if;
      end Add_Unique;

      procedure Collect_Expr (Expr : CM.Expr_Access);
      procedure Collect
        (Statements : CM.Statement_Access_Vectors.Vector);

      procedure Collect_Expr (Expr : CM.Expr_Access) is
      begin
         if Expr = null then
            return;
         end if;

         case Expr.Kind is
            when CM.Expr_Select | CM.Expr_Resolved_Index =>
               if Expr.Prefix /= null
                 and then Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
               then
                  declare
                     Param_Name : constant String := Root_Name (Expr.Prefix);
                  begin
                     if Param_Name'Length > 0
                       and then Needs_Non_Null_Param_Check (Param_Name)
                       and then not Has_Leading_Null_Return_Guard (Param_Name)
                     then
                        Add_Unique ("(" & Param_Name & " /= null)");
                     end if;
                  end;
               end if;
            when others =>
               null;
         end case;

         Collect_Expr (Expr.Prefix);
         Collect_Expr (Expr.Callee);
         Collect_Expr (Expr.Inner);
         Collect_Expr (Expr.Left);
         Collect_Expr (Expr.Right);
         Collect_Expr (Expr.Value);
         Collect_Expr (Expr.Target);
         for Arg of Expr.Args loop
            Collect_Expr (Arg);
         end loop;
         for Field of Expr.Fields loop
            Collect_Expr (Field.Expr);
         end loop;
         for Element of Expr.Elements loop
            Collect_Expr (Element);
         end loop;
      end Collect_Expr;

      procedure Collect
        (Statements : CM.Statement_Access_Vectors.Vector) is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Assign =>
                     declare
                        Target_Name : constant String := Root_Name (Item.Target);
                        Target_Type : constant String := FT.To_String (Item.Target.Type_Name);
                     begin
                        if Target_Name'Length > 0
                          and then Is_Alias_Param_Name (Target_Name)
                          and then Is_Integer_Type (Unit, Document, Target_Type)
                          and then Uses_Wide_Value (Unit, Document, State, Item.Value)
                        then
                           declare
                              Wide_Image : constant String :=
                                Render_Wide_Expr (Unit, Document, Item.Value, State);
                           begin
                              Add_Unique
                                ("("
                                 & Wide_Image
                                 & " >= Safe_Runtime.Wide_Integer ("
                                 & Target_Type
                                 & "'First) and then "
                                 & Wide_Image
                                 & " <= Safe_Runtime.Wide_Integer ("
                                 & Target_Type
                                 & "'Last))");
                           end;
                        end if;
                        Collect_Expr (Item.Target);
                        Collect_Expr (Item.Value);
                     end;
                  when CM.Stmt_Call =>
                     Collect_Expr (Item.Call);
                  when CM.Stmt_Return =>
                     Collect_Expr (Item.Value);
                  when CM.Stmt_If =>
                     Collect_Expr (Item.Condition);
                     Collect (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Collect_Expr (Part.Condition);
                        Collect (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Collect (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     Collect_Expr (Item.Case_Expr);
                     for Arm of Item.Case_Arms loop
                        Collect_Expr (Arm.Choice);
                        Collect (Arm.Statements);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     Collect_Expr (Item.Condition);
                     Collect_Expr (Item.Loop_Range.Name_Expr);
                     Collect_Expr (Item.Loop_Range.Low_Expr);
                     Collect_Expr (Item.Loop_Range.High_Expr);
                     Collect_Expr (Item.Loop_Iterable);
                     Collect (Item.Body_Stmts);
                  when CM.Stmt_Object_Decl =>
                     Collect_Expr (Item.Decl.Initializer);
                  when CM.Stmt_Destructure_Decl =>
                     Collect_Expr (Item.Destructure.Initializer);
                  when CM.Stmt_Send | CM.Stmt_Receive | CM.Stmt_Try_Send | CM.Stmt_Try_Receive =>
                     Collect_Expr (Item.Channel_Name);
                     Collect_Expr (Item.Value);
                     Collect_Expr (Item.Target);
                     Collect_Expr (Item.Success_Var);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect_Expr (Arm.Channel_Data.Channel_Name);
                              Collect (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Collect_Expr (Arm.Delay_Data.Duration_Expr);
                              Collect (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when CM.Stmt_Delay =>
                     Collect_Expr (Item.Value);
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Collect;

      Result : SU.Unbounded_String;
   begin
      for Param of Subprogram.Params loop
         if Is_Float_Type (Unit, Document, Param.Type_Info)
           and then Param.Type_Info.Has_Float_Low_Text
           and then Param.Type_Info.Has_Float_High_Text
         then
            Add_Unique
              ("("
               & FT.To_String (Param.Name)
               & " >= "
               & FT.To_String (Param.Type_Info.Float_Low_Text)
               & " and then "
               & FT.To_String (Param.Name)
               & " <= "
               & FT.To_String (Param.Type_Info.Float_High_Text)
               & ")");
         end if;
      end loop;
      Collect (Subprogram.Statements);
      for Index in Conditions.First_Index .. Conditions.Last_Index loop
         if Index /= Conditions.First_Index then
            Result := Result & SU.To_Unbounded_String (" and then ");
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Conditions (Index)));
      end loop;
      return SU.To_String (Result);
   end Render_Access_Param_Precondition;

   function Exprs_Match
     (Left  : CM.Expr_Access;
      Right : CM.Expr_Access) return Boolean
   is
   begin
      if Left = null or else Right = null then
         return Left = Right;
      elsif Left.Kind /= Right.Kind then
         return False;
      end if;

      case Left.Kind is
         when CM.Expr_Int =>
            return FT.To_String (Left.Text) = FT.To_String (Right.Text)
              and then Left.Int_Value = Right.Int_Value;
         when CM.Expr_Real =>
            return FT.To_String (Left.Text) = FT.To_String (Right.Text);
         when CM.Expr_String =>
            return FT.To_String (Left.Text) = FT.To_String (Right.Text);
         when CM.Expr_Bool =>
            return Left.Bool_Value = Right.Bool_Value;
         when CM.Expr_Null =>
            return True;
         when CM.Expr_Ident =>
            return FT.To_String (Left.Name) = FT.To_String (Right.Name);
         when CM.Expr_Select =>
            return FT.To_String (Left.Selector) = FT.To_String (Right.Selector)
              and then Exprs_Match (Left.Prefix, Right.Prefix);
         when CM.Expr_Resolved_Index =>
            if not Exprs_Match (Left.Prefix, Right.Prefix)
              or else Left.Args.Length /= Right.Args.Length
            then
               return False;
            end if;
            for Index in Left.Args.First_Index .. Left.Args.Last_Index loop
               if not Exprs_Match (Left.Args (Index), Right.Args (Index)) then
                  return False;
               end if;
            end loop;
            return True;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            return Exprs_Match (Left.Target, Right.Target)
              and then Exprs_Match (Left.Inner, Right.Inner);
         when CM.Expr_Unary =>
            return FT.To_String (Left.Operator) = FT.To_String (Right.Operator)
              and then Exprs_Match (Left.Inner, Right.Inner);
         when CM.Expr_Binary =>
            return FT.To_String (Left.Operator) = FT.To_String (Right.Operator)
              and then Exprs_Match (Left.Left, Right.Left)
              and then Exprs_Match (Left.Right, Right.Right);
         when others =>
            return False;
      end case;
   end Exprs_Match;

   function Expr_Contains_Target
     (Expr   : CM.Expr_Access;
      Target : CM.Expr_Access) return Boolean
   is
   begin
      if Expr = null or else Target = null then
         return False;
      elsif Exprs_Match (Expr, Target) then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Select =>
            return Expr_Contains_Target (Expr.Prefix, Target);
         when CM.Expr_Resolved_Index | CM.Expr_Call =>
            if Expr_Contains_Target (Expr.Prefix, Target)
              or else Expr_Contains_Target (Expr.Callee, Target)
            then
               return True;
            end if;
            for Item of Expr.Args loop
               if Expr_Contains_Target (Item, Target) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            return
              Expr_Contains_Target (Expr.Target, Target)
              or else Expr_Contains_Target (Expr.Inner, Target);
         when CM.Expr_Unary =>
            return Expr_Contains_Target (Expr.Inner, Target);
         when CM.Expr_Binary =>
            return
              Expr_Contains_Target (Expr.Left, Target)
              or else Expr_Contains_Target (Expr.Right, Target);
         when CM.Expr_Aggregate =>
            for Field of Expr.Fields loop
               if Expr_Contains_Target (Field.Expr, Target) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Contains_Target;

   function Render_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String
   is
      Result : SU.Unbounded_String;
   begin
      if not Supported then
         return "";
      elsif Expr = null or else Target = null then
         Supported := False;
         return "";
      elsif Exprs_Match (Expr, Target) then
         return Replacement;
      end if;

      case Expr.Kind is
         when CM.Expr_Int | CM.Expr_Real | CM.Expr_String
            | CM.Expr_Bool | CM.Expr_Null | CM.Expr_Ident =>
            return Render_Expr (Unit, Document, Expr, State);
         when CM.Expr_Select =>
            declare
               Prefix_Image  : constant String :=
                 Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Prefix, Target, Replacement, State, Supported);
               Selector_Name : constant String := FT.To_String (Expr.Selector);
            begin
               if not Supported then
                  return "";
               elsif Selector_Name = "access"
                 and then Expr.Prefix /= null
                 and then Has_Text (Expr.Prefix.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
                 and then Is_Access_Type
                   (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
               then
                  return Prefix_Image;
               elsif Is_Attribute_Selector (Selector_Name)
                 and then not
                   (Expr.Prefix /= null
                    and then Expr.Prefix.Kind = CM.Expr_Select
                    and then FT.To_String (Expr.Prefix.Selector) = "all")
                 and then not Selector_Is_Record_Field (Unit, Document, Expr.Prefix, Selector_Name)
               then
                  return Prefix_Image & "'" & Selector_Name;
               elsif Expr.Prefix /= null
                 and then FT.Lowercase (Selector_Name) = "message"
                 and then Has_Text (Expr.Prefix.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
                 and then Is_Result_Builtin
                   (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
               then
                  State.Needs_Ada_Strings_Unbounded := True;
                  return "Ada.Strings.Unbounded.To_String (" & Prefix_Image & ".Message)";
               end if;
               return Prefix_Image & "." & Selector_Name;
            end;
         when CM.Expr_Resolved_Index =>
            Result :=
              SU.To_Unbounded_String
                (Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Prefix, Target, Replacement, State, Supported)
                 & " (");
            if not Supported then
               return "";
            end if;
            for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
               if Index /= Expr.Args.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Render_Expr_With_Target_Substitution
                        (Unit, Document, Expr.Args (Index), Target, Replacement, State, Supported));
               if not Supported then
                  return "";
               end if;
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Conversion =>
            declare
               Target_Image : constant String :=
                 (if Has_Text (Expr.Type_Name)
                     then Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name))
                  else
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Target, Target, Replacement, State, Supported));
            begin
               return
                 Target_Image
                 & " ("
                 & Render_Expr_With_Target_Substitution
                     (Unit, Document, Expr.Inner, Target, Replacement, State, Supported)
                 & ")";
            end;
         when CM.Expr_Subtype_Indication =>
            if Has_Text (Expr.Type_Name) then
               return Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name));
            end if;
            Supported := False;
            return "";
         when CM.Expr_Call =>
            declare
               Callee_Flat  : constant String := CM.Flatten_Name (Expr.Callee);
               Lower_Callee : constant String := FT.Lowercase (Callee_Flat);
               Callee_Image : SU.Unbounded_String;
            begin
               if Expr.Callee /= null
                 and then Expr.Callee.Kind = CM.Expr_Select
                 and then FT.To_String (Expr.Callee.Selector) = "access"
                 and then Expr.Callee.Prefix /= null
                 and then Has_Text (Expr.Callee.Prefix.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name))
                 and then Is_Access_Type
                   (Lookup_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name)))
               then
                  Callee_Image :=
                    SU.To_Unbounded_String
                      (Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Callee.Prefix,
                          Target,
                          Replacement,
                          State,
                          Supported));
               elsif Expr.Callee /= null
                 and then Expr.Callee.Kind = CM.Expr_Select
                 and then Is_Attribute_Selector (FT.To_String (Expr.Callee.Selector))
                 and then not
                   (Expr.Callee.Prefix /= null
                    and then Expr.Callee.Prefix.Kind = CM.Expr_Select
                    and then FT.To_String (Expr.Callee.Prefix.Selector) = "all")
                 and then not
                   Selector_Is_Record_Field
                     (Unit,
                      Document,
                      Expr.Callee.Prefix,
                      FT.To_String (Expr.Callee.Selector))
               then
                  Callee_Image :=
                    SU.To_Unbounded_String
                      (Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Callee.Prefix,
                          Target,
                          Replacement,
                          State,
                          Supported)
                       & "'"
                       & FT.To_String (Expr.Callee.Selector));
               else
                  Callee_Image :=
                    SU.To_Unbounded_String
                      (Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Callee,
                          Target,
                          Replacement,
                          State,
                          Supported));
               end if;

               if not Supported then
                  return "";
               elsif Lower_Callee = "ok" and then Expr.Args.Is_Empty then
                  State.Needs_Ada_Strings_Unbounded := True;
                  return Render_Result_Empty_Aggregate;
               elsif Lower_Callee = "fail" and then Natural (Expr.Args.Length) = 1 then
                  declare
                     Message_Image : constant String :=
                       Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Args (Expr.Args.First_Index),
                          Target,
                          Replacement,
                          State,
                          Supported);
                  begin
                     if not Supported then
                        return "";
                     end if;
                     State.Needs_Ada_Strings_Unbounded := True;
                     return Render_Result_Fail_Aggregate (Message_Image);
                  end;
               elsif Expr.Args.Is_Empty then
                  return SU.To_String (Callee_Image);
               end if;

               Result := Callee_Image & SU.To_Unbounded_String (" (");
            end;
            for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
               if Index /= Expr.Args.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Render_Expr_With_Target_Substitution
                        (Unit,
                         Document,
                         Expr.Args (Index),
                         Target,
                         Replacement,
                         State,
                         Supported));
               if not Supported then
                  return "";
               end if;
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Aggregate =>
            Result := SU.To_Unbounded_String ("(");
            for Index in Expr.Fields.First_Index .. Expr.Fields.Last_Index loop
               declare
                  Field : constant CM.Aggregate_Field := Expr.Fields (Index);
               begin
                  if Index /= Expr.Fields.First_Index then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (FT.To_String (Field.Field_Name)
                         & " => "
                         & Render_Expr_With_Target_Substitution
                             (Unit,
                              Document,
                              Field.Expr,
                              Target,
                              Replacement,
                              State,
                              Supported));
                  if not Supported then
                     return "";
                  end if;
               end;
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Annotated =>
            declare
               Target_Image : constant String :=
                 Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Target, Target, Replacement, State, Supported);
               Inner_Image  : constant String :=
                 Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Inner, Target, Replacement, State, Supported);
            begin
               if not Supported then
                  return "";
               end if;
               return
                 Target_Image
                 & "'"
                 & (if Expr.Inner /= null and then Expr.Inner.Kind = CM.Expr_Aggregate
                    then Inner_Image
                    else "(" & Inner_Image & ")");
            end;
         when CM.Expr_Unary =>
            if FT.To_String (Expr.Operator) = "not"
              and then Has_Text (Expr.Type_Name)
              and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Type_Name))
            then
               declare
                  Inner_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Inner, Target, Replacement, State, Supported);
               begin
                  if not Supported then
                     return "";
                  end if;
                  return Render_Binary_Unary_Image (Unit, Document, Expr, Inner_Image);
               end;
            end if;
            return
               "("
               & Map_Operator (FT.To_String (Expr.Operator))
               & (if FT.To_String (Expr.Operator) = "not" then " " else "")
               & Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Inner, Target, Replacement, State, Supported)
               & ")";
         when CM.Expr_Binary =>
            if Expr.Left /= null
              and then Has_Text (Expr.Left.Type_Name)
              and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Left.Type_Name))
            then
               declare
                  Left_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Left, Target, Replacement, State, Supported);
                  Right_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Right, Target, Replacement, State, Supported);
               begin
                  if not Supported then
                     return "";
                  end if;
                  return
                    Render_Binary_Operation_Image
                      (Unit, Document, Expr, Left_Image, Right_Image);
               end;
            end if;
            return
              "("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr.Left, Target, Replacement, State, Supported)
              & " "
              & Map_Operator (FT.To_String (Expr.Operator))
              & " "
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr.Right, Target, Replacement, State, Supported)
              & ")";
         when others =>
            Supported := False;
            return "";
      end case;
   end Render_Expr_With_Target_Substitution;

   function Render_Expr_With_Old_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String
   is
   begin
      if Target = null then
         Supported := False;
         return "";
      end if;

      return
        Render_Expr_With_Target_Substitution
          (Unit,
           Document,
           Expr,
           Target,
           Render_Expr (Unit, Document, Target, State) & "'Old",
           State,
           Supported);
   end Render_Expr_With_Old_Substitution;

   function Render_Access_Param_Postcondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Conditions   : FT.UString_Vectors.Vector;
      Seen_Targets : FT.UString_Vectors.Vector;
      Unsupported  : Boolean := False;

      function Is_Alias_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then Param.Type_Info.Anonymous
              and then Is_Alias_Access (Param.Type_Info)
              and then not Param.Type_Info.Is_Constant
            then
               return True;
            end if;
         end loop;
         return False;
      end Is_Alias_Param_Name;

      procedure Add_Unique_Equality
        (Target_Expr : CM.Expr_Access;
         Value_Expr  : CM.Expr_Access)
      is
         Target_Image : constant String := Render_Expr (Unit, Document, Target_Expr, State);
         Supported    : Boolean := True;
         Value_Image  : constant String :=
           Render_Expr_With_Old_Substitution
             (Unit, Document, Value_Expr, Target_Expr, State, Supported);
      begin
         if not Supported or else Target_Image'Length = 0 or else Value_Image'Length = 0 then
            Unsupported := True;
            return;
         end if;

         if Contains_Name (Seen_Targets, Target_Image) then
            Unsupported := True;
            return;
         end if;

         Seen_Targets.Append (FT.To_UString (Target_Image));
         Conditions.Append
           (FT.To_UString
              (Target_Image & " = " & Value_Image));
      end Add_Unique_Equality;

      procedure Add_Unique_Condition (Condition : String) is
      begin
         if Condition'Length > 0 and then not Contains_Name (Conditions, Condition) then
            Conditions.Append (FT.To_UString (Condition));
         end if;
      end Add_Unique_Condition;

      Result : SU.Unbounded_String;
   begin
      for Item of Subprogram.Statements loop
         exit when Unsupported;

         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Assign =>
                  declare
                     Target_Name : constant String := Root_Name (Item.Target);
                  begin
                     if Target_Name'Length > 0
                       and then Is_Alias_Param_Name (Target_Name)
                     then
                        Add_Unique_Equality (Item.Target, Item.Value);
                     end if;
                  end;
               when CM.Stmt_If
                  | CM.Stmt_Case
                  | CM.Stmt_While
                  | CM.Stmt_For
                  | CM.Stmt_Loop
                  | CM.Stmt_Select =>
                  Unsupported := True;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      for Param of Subprogram.Params loop
         declare
            Mode : constant String := FT.To_String (Param.Mode);
            Name : constant String := FT.To_String (Param.Name);
         begin
            if Name'Length > 0
              and then Is_Owner_Access (Param.Type_Info)
              and then Mode in "mut" | "in out"
            then
               Add_Unique_Condition (Name & " /= null");
            end if;
         end;
      end loop;

      if Unsupported or else Conditions.Is_Empty then
         return "";
      end if;

      State.Needs_Unevaluated_Use_Of_Old := True;
      for Index in Conditions.First_Index .. Conditions.Last_Index loop
         if Index /= Conditions.First_Index then
            Result := Result & SU.To_Unbounded_String (" and then ");
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Conditions (Index)));
      end loop;
      return SU.To_String (Result);
   end Render_Access_Param_Postcondition;

   function Render_Subprogram_Aspects
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Bronze     : MB.Bronze_Result;
      State      : in out Emit_State) return String
   is
      Summary : constant MB.Graph_Summary :=
        Find_Graph_Summary (Bronze, FT.To_String (Subprogram.Name));
      Uses_Print : constant Boolean := Statements_Use_Print (Subprogram.Statements);
      Uses_Structural_Traversal : constant Boolean :=
        Uses_Structural_Traversal_Lowering (Subprogram);
      Global_Image  : constant String := Render_Global_Aspect (Unit, Summary);
      Depends_Image : constant String :=
        Render_Depends_Aspect (Unit, Subprogram, Summary);
      Pre_Image : constant String :=
        Render_Access_Param_Precondition (Unit, Document, Subprogram, State);
      Post_Image : constant String :=
        Render_Access_Param_Postcondition (Unit, Document, Subprogram, State);
      Structural_Pre_Image : constant String :=
        (if Uses_Structural_Traversal and then Subprogram.Params.Length >= 3
         then
           Structural_Accumulator_Count_Total_Bound
             (Unit,
              Document,
              Subprogram,
              Ada_Safe_Name
                (FT.To_String
                   (Subprogram.Params (Subprogram.Params.First_Index + 1).Name)),
              Ada_Safe_Name
                (FT.To_String
                   (Subprogram.Params (Subprogram.Params.First_Index + 2).Name)),
              State)
         else "");
      Local_Names : FT.UString_Vectors.Vector;
      function Recursive_Variant_Image return String;
      Result : SU.Unbounded_String;
      Has_Aspect : Boolean := False;

      procedure Append_Aspect (Text : String) is
      begin
         if not Has_Aspect then
            Result := Result & SU.To_Unbounded_String (" with " & Text);
            Has_Aspect := True;
         else
            Result :=
              Result
              & SU.To_Unbounded_String
                  ("," & ASCII.LF
                   & Indentation (4)
                   & Text);
         end if;
      end Append_Aspect;

      function Recursive_Variant_Image return String is
         Subprogram_Name : constant String :=
           FT.Lowercase (FT.To_String (Subprogram.Name));

         function Variant_From_Expr (Expr : CM.Expr_Access) return String;
         function Variant_From_Statements
           (Statements : CM.Statement_Access_Vectors.Vector) return String;

         function Variant_From_Expr (Expr : CM.Expr_Access) return String is
            Result : constant String := "";
         begin
            if Expr = null then
               return "";
            end if;

            case Expr.Kind is
               when CM.Expr_Call =>
                  if Expr.Callee /= null
                    and then FT.Lowercase (CM.Flatten_Name (Expr.Callee)) = Subprogram_Name
                  then
                     for Index in Subprogram.Params.First_Index .. Subprogram.Params.Last_Index loop
                        exit when Expr.Args.Is_Empty or else Index > Expr.Args.Last_Index;

                        declare
                           Param      : constant CM.Symbol := Subprogram.Params (Index);
                           Mode       : constant String := FT.Lowercase (FT.To_String (Param.Mode));
                           Param_Name : constant String := FT.To_String (Param.Name);
                           Root       : constant String := Root_Name (Expr.Args (Index));
                        begin
                           if Param_Name'Length > 0
                             and then Root = Param_Name
                             and then Is_Owner_Access (Param.Type_Info)
                             and then Mode /= "mut"
                             and then Mode /= "in out"
                             and then Mode /= "out"
                           then
                              return "Structural => " & Param_Name;
                           end if;
                        end;
                     end loop;
                  end if;

                  declare
                     Callee_Result : constant String := Variant_From_Expr (Expr.Callee);
                  begin
                     if Callee_Result'Length > 0 then
                        return Callee_Result;
                     end if;
                  end;

                  if not Expr.Args.Is_Empty then
                     for Arg of Expr.Args loop
                        declare
                           Arg_Result : constant String := Variant_From_Expr (Arg);
                        begin
                           if Arg_Result'Length > 0 then
                              return Arg_Result;
                           end if;
                        end;
                     end loop;
                  end if;
               when CM.Expr_Select =>
                  return Variant_From_Expr (Expr.Prefix);
               when CM.Expr_Apply
                  | CM.Expr_Resolved_Index
                  | CM.Expr_Tuple
                  | CM.Expr_Array_Literal =>
                  if not Expr.Args.Is_Empty then
                     for Arg of Expr.Args loop
                        declare
                           Arg_Result : constant String := Variant_From_Expr (Arg);
                        begin
                           if Arg_Result'Length > 0 then
                              return Arg_Result;
                           end if;
                        end;
                     end loop;
                  end if;
               when CM.Expr_Conversion
                  | CM.Expr_Annotated
                  | CM.Expr_Unary =>
                  return Variant_From_Expr (Expr.Inner);
               when CM.Expr_Aggregate =>
                  for Field of Expr.Fields loop
                     declare
                        Field_Result : constant String := Variant_From_Expr (Field.Expr);
                     begin
                        if Field_Result'Length > 0 then
                           return Field_Result;
                        end if;
                     end;
                  end loop;
               when CM.Expr_Binary =>
                  declare
                     Left_Result : constant String := Variant_From_Expr (Expr.Left);
                  begin
                     if Left_Result'Length > 0 then
                        return Left_Result;
                     end if;
                  end;
                  return Variant_From_Expr (Expr.Right);
               when others =>
                  null;
            end case;

            return Result;
         end Variant_From_Expr;

         function Variant_From_Statements
           (Statements : CM.Statement_Access_Vectors.Vector) return String
         is
         begin
            for Item of Statements loop
               if Item = null then
                  null;
               else
                  case Item.Kind is
                     when CM.Stmt_Object_Decl =>
                        if Item.Decl.Has_Initializer then
                           declare
                              Initializer_Result : constant String :=
                                Variant_From_Expr (Item.Decl.Initializer);
                           begin
                              if Initializer_Result'Length > 0 then
                                 return Initializer_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Destructure_Decl =>
                        if Item.Destructure.Has_Initializer then
                           declare
                              Initializer_Result : constant String :=
                                Variant_From_Expr (Item.Destructure.Initializer);
                           begin
                              if Initializer_Result'Length > 0 then
                                 return Initializer_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Assign =>
                        declare
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                        begin
                           if Value_Result'Length > 0 then
                              return Value_Result;
                           end if;
                        end;
                     when CM.Stmt_Call | CM.Stmt_Return | CM.Stmt_Send | CM.Stmt_Delay =>
                        declare
                           Call_Result : constant String := Variant_From_Expr (Item.Call);
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                        begin
                           if Call_Result'Length > 0 then
                              return Call_Result;
                           elsif Value_Result'Length > 0 then
                              return Value_Result;
                           end if;
                        end;
                     when CM.Stmt_Receive | CM.Stmt_Try_Send | CM.Stmt_Try_Receive =>
                        declare
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                           Success_Result : constant String := Variant_From_Expr (Item.Success_Var);
                        begin
                           if Value_Result'Length > 0 then
                              return Value_Result;
                           elsif Success_Result'Length > 0 then
                              return Success_Result;
                           end if;
                        end;
                     when CM.Stmt_If =>
                        declare
                           Condition_Result : constant String :=
                             Variant_From_Expr (Item.Condition);
                        begin
                           if Condition_Result'Length > 0 then
                              return Condition_Result;
                           end if;
                        end;
                        declare
                           Then_Result : constant String :=
                             Variant_From_Statements (Item.Then_Stmts);
                        begin
                           if Then_Result'Length > 0 then
                              return Then_Result;
                           end if;
                        end;
                        for Part of Item.Elsifs loop
                           declare
                              Condition_Result : constant String :=
                                Variant_From_Expr (Part.Condition);
                           begin
                              if Condition_Result'Length > 0 then
                                 return Condition_Result;
                              end if;
                           end;
                           declare
                              Elsif_Result : constant String :=
                                Variant_From_Statements (Part.Statements);
                           begin
                              if Elsif_Result'Length > 0 then
                                 return Elsif_Result;
                              end if;
                           end;
                        end loop;
                        if Item.Has_Else then
                           declare
                              Else_Result : constant String :=
                                Variant_From_Statements (Item.Else_Stmts);
                           begin
                              if Else_Result'Length > 0 then
                                 return Else_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Case =>
                        declare
                           Expr_Result : constant String :=
                             Variant_From_Expr (Item.Case_Expr);
                        begin
                           if Expr_Result'Length > 0 then
                              return Expr_Result;
                           end if;
                        end;
                        for Arm of Item.Case_Arms loop
                           declare
                              Arm_Result : constant String :=
                                Variant_From_Statements (Arm.Statements);
                           begin
                              if Arm_Result'Length > 0 then
                                 return Arm_Result;
                              end if;
                           end;
                        end loop;
                     when CM.Stmt_While =>
                        declare
                           Condition_Result : constant String :=
                             Variant_From_Expr (Item.Condition);
                        begin
                           if Condition_Result'Length > 0 then
                              return Condition_Result;
                           end if;
                        end;
                        declare
                           Body_Result : constant String :=
                             Variant_From_Statements (Item.Body_Stmts);
                        begin
                           if Body_Result'Length > 0 then
                              return Body_Result;
                           end if;
                        end;
                     when CM.Stmt_For | CM.Stmt_Loop =>
                        declare
                           Body_Result : constant String :=
                             Variant_From_Statements (Item.Body_Stmts);
                        begin
                           if Body_Result'Length > 0 then
                              return Body_Result;
                           end if;
                        end;
                     when CM.Stmt_Select =>
                        for Arm of Item.Arms loop
                           declare
                              Arm_Result : constant String :=
                                Variant_From_Statements
                                  ((case Arm.Kind is
                                     when CM.Select_Arm_Channel => Arm.Channel_Data.Statements,
                                     when CM.Select_Arm_Delay => Arm.Delay_Data.Statements,
                                     when others => CM.Statement_Access_Vectors.Empty_Vector));
                           begin
                              if Arm_Result'Length > 0 then
                                 return Arm_Result;
                              end if;
                           end;
                        end loop;
                     when others =>
                        null;
                  end case;
               end if;
            end loop;

            return "";
         end Variant_From_Statements;
      begin
         for Decl of Subprogram.Declarations loop
            for Name of Decl.Names loop
               if FT.To_String (Name)'Length > 0 then
                  Local_Names.Append (Name);
               end if;
            end loop;
         end loop;

         return Variant_From_Statements (Subprogram.Statements);
      end Recursive_Variant_Image;
   begin
      if Uses_Print then
         Append_Aspect ("SPARK_Mode => Off");
      end if;

      if Has_Text (Summary.Name) then
         if not Uses_Structural_Traversal then
            declare
               Variant_Image : constant String := Recursive_Variant_Image;
            begin
               if Variant_Image'Length > 0 then
                  Append_Aspect ("Subprogram_Variant => (" & Variant_Image & ")");
                  if Contains_Recursive_Accumulator_Pattern
                       (FT.Lowercase (FT.To_String (Subprogram.Name)),
                        Local_Names,
                        Subprogram.Statements)
                  then
                     Append_Aspect ("Annotate => (GNATprove, Skip_Proof)");
                  end if;
               end if;
            end;
         end if;

         Append_Aspect ("Global => " & Global_Image);

         if Depends_Image'Length > 0 then
            Append_Aspect ("Depends => (" & Depends_Image & ")");
         end if;
         if Pre_Image'Length > 0 or else Structural_Pre_Image'Length > 0 then
            Append_Aspect
              ("Pre => "
               & (if Pre_Image'Length > 0 and then Structural_Pre_Image'Length > 0
                  then Pre_Image & " and then " & Structural_Pre_Image
                  elsif Pre_Image'Length > 0
                  then Pre_Image
                  else Structural_Pre_Image));
         end if;
         if Post_Image'Length > 0 then
            Append_Aspect ("Post => " & Post_Image);
         end if;
      end if;

      return SU.To_String (Result);
   end Render_Subprogram_Aspects;

   function Render_Discrete_Range
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Item_Range : CM.Discrete_Range;
      State    : in out Emit_State) return String
   is
   begin
      case Item_Range.Kind is
         when CM.Range_Subtype =>
            return Render_Expr (Unit, Document, Item_Range.Name_Expr, State);
         when CM.Range_Explicit =>
            return
              Render_Expr (Unit, Document, Item_Range.Low_Expr, State)
              & " .. "
              & Render_Expr (Unit, Document, Item_Range.High_Expr, State);
         when others =>
            Raise_Unsupported
              (State,
               Item_Range.Span,
               "unsupported loop range in Ada emission");
      end case;
   end Render_Discrete_Range;

   function Statement_Contains_Exit
     (Item : CM.Statement_Access) return Boolean
   is
   begin
      if Item = null then
         return False;
      end if;

      case Item.Kind is
         when CM.Stmt_Exit =>
            return True;
         when CM.Stmt_If =>
            if Statements_Contain_Exit (Item.Then_Stmts) then
               return True;
            end if;
            for Part of Item.Elsifs loop
               if Statements_Contain_Exit (Part.Statements) then
                  return True;
               end if;
            end loop;
            return Item.Has_Else and then Statements_Contain_Exit (Item.Else_Stmts);
         when CM.Stmt_Case =>
            for Arm of Item.Case_Arms loop
               if Statements_Contain_Exit (Arm.Statements) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Stmt_Loop | CM.Stmt_While | CM.Stmt_For =>
            return Statements_Contain_Exit (Item.Body_Stmts);
         when others =>
            return False;
      end case;
   end Statement_Contains_Exit;

   function Statements_Contain_Exit
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
   is
   begin
      for Item of Statements loop
         if Statement_Contains_Exit (Item) then
            return True;
         end if;
      end loop;
      return False;
   end Statements_Contain_Exit;

   function Statement_Falls_Through
     (Item : CM.Statement_Access) return Boolean
   is
   begin
      if Item = null then
         return True;
      end if;

      case Item.Kind is
         when CM.Stmt_Return =>
            return False;
         when CM.Stmt_If =>
            if Statements_Fall_Through (Item.Then_Stmts) then
               return True;
            end if;
            for Part of Item.Elsifs loop
               if Statements_Fall_Through (Part.Statements) then
                  return True;
               end if;
            end loop;
            if not Item.Has_Else then
               return True;
            end if;
            return Statements_Fall_Through (Item.Else_Stmts);
         when CM.Stmt_Case =>
            for Arm of Item.Case_Arms loop
               if Statements_Fall_Through (Arm.Statements) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Stmt_Loop =>
            return Statements_Contain_Exit (Item.Body_Stmts);
         when others =>
            return True;
      end case;
   end Statement_Falls_Through;

   function Statements_Fall_Through
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
   is
   begin
      if Statements.Is_Empty then
         return True;
      end if;

      for Item of Statements loop
         if not Statement_Falls_Through (Item) then
            return False;
         end if;
      end loop;
      return True;
   end Statements_Fall_Through;

   function Loop_Variant_Image
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Condition : CM.Expr_Access;
      State     : in out Emit_State) return String
   is
      Operator : constant String :=
        (if Condition = null then "" else Map_Operator (FT.To_String (Condition.Operator)));
   begin
      if Condition = null or else Condition.Kind /= CM.Expr_Binary then
         return "";
      end if;

      if Operator = "/=" then
         declare
            Cursor : CM.Expr_Access := null;
         begin
            if Condition.Left /= null and then Condition.Left.Kind /= CM.Expr_Null
              and then Condition.Right /= null and then Condition.Right.Kind = CM.Expr_Null
            then
               Cursor := Condition.Left;
            elsif Condition.Right /= null and then Condition.Right.Kind /= CM.Expr_Null
              and then Condition.Left /= null and then Condition.Left.Kind = CM.Expr_Null
            then
               Cursor := Condition.Right;
            end if;

            if Cursor /= null then
               declare
                  Flattened : constant String := CM.Flatten_Name (Cursor);
               begin
                  if Flattened'Length > 0 then
                     return "Structural => " & Flattened;
                  end if;
               end;
            end if;
         end;
      elsif Operator in "<" | "<=" then
         if Condition.Left /= null
           and then Condition.Right /= null
           and then Condition.Left.Kind = CM.Expr_Ident
           and then Condition.Right.Kind = CM.Expr_Ident
           and then Is_Integer_Type (Unit, Document, FT.To_String (Condition.Left.Type_Name))
           and then Is_Integer_Type (Unit, Document, FT.To_String (Condition.Right.Type_Name))
           then
            return
              "Increases => "
              & FT.To_String (Condition.Left.Name)
              & ", Decreases => "
              & FT.To_String (Condition.Right.Name);
         end if;
      elsif Operator = "=" then
         declare
            function Is_Length_Select (Expr : CM.Expr_Access) return Boolean is
            begin
               return
                 Expr /= null
                 and then Expr.Kind = CM.Expr_Select
                 and then FT.To_String (Expr.Selector) = "length";
            end Is_Length_Select;
         begin
            if (Is_Length_Select (Condition.Left)
                and then Condition.Right /= null
                and then Condition.Right.Kind = CM.Expr_Int)
              or else
              (Is_Length_Select (Condition.Right)
               and then Condition.Left /= null
               and then Condition.Left.Kind = CM.Expr_Int)
            then
               return
                 "Decreases => Long_Long_Integer'(if "
                 & Render_Expr (Unit, Document, Condition, State)
                 & " then 1 else 0)";
            end if;
         end;
      end if;

      return "";
   end Loop_Variant_Image;

   function Contains_Recursive_Accumulator_Pattern
     (Subprogram_Name : String;
      Local_Names     : FT.UString_Vectors.Vector;
      Statements      : CM.Statement_Access_Vectors.Vector) return Boolean
   is
      function Is_Local_Name (Name : String) return Boolean is
      begin
         return Name'Length > 0 and then Contains_Name (Local_Names, Name);
      end Is_Local_Name;

      function Is_Recursive_Call (Expr : CM.Expr_Access) return Boolean is
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Call
           and then Expr.Callee /= null
           and then FT.Lowercase (CM.Flatten_Name (Expr.Callee)) = Subprogram_Name;
      end Is_Recursive_Call;

      function Returns_Local_Name
        (Statements : CM.Statement_Access_Vectors.Vector;
         Name       : String) return Boolean;

      function Contains_Pattern
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;

      function Returns_Local_Name
        (Statements : CM.Statement_Access_Vectors.Vector;
         Name       : String) return Boolean
      is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Return =>
                     if Root_Name (Item.Value) = Name then
                        return True;
                     end if;
                  when CM.Stmt_If =>
                     if Returns_Local_Name (Item.Then_Stmts, Name) then
                        return True;
                     end if;
                     for Part of Item.Elsifs loop
                        if Returns_Local_Name (Part.Statements, Name) then
                           return True;
                        end if;
                     end loop;
                     if Item.Has_Else
                       and then Returns_Local_Name (Item.Else_Stmts, Name)
                     then
                        return True;
                     end if;
                  when CM.Stmt_Case =>
                     for Arm of Item.Case_Arms loop
                        if Returns_Local_Name (Arm.Statements, Name) then
                           return True;
                        end if;
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     if Returns_Local_Name (Item.Body_Stmts, Name) then
                        return True;
                     end if;
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              if Returns_Local_Name (Arm.Channel_Data.Statements, Name) then
                                 return True;
                              end if;
                           when CM.Select_Arm_Delay =>
                              if Returns_Local_Name (Arm.Delay_Data.Statements, Name) then
                                 return True;
                              end if;
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;

         return False;
      end Returns_Local_Name;

      function Contains_Pattern
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
      is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Assign =>
                     declare
                        Target_Name : constant String := Root_Name (Item.Target);
                     begin
                        if Is_Local_Name (Target_Name)
                          and then Is_Recursive_Call (Item.Value)
                          and then Returns_Local_Name (Statements, Target_Name)
                        then
                           return True;
                        end if;
                     end;
                  when CM.Stmt_If =>
                     if Contains_Pattern (Item.Then_Stmts) then
                        return True;
                     end if;
                     for Part of Item.Elsifs loop
                        if Contains_Pattern (Part.Statements) then
                           return True;
                        end if;
                     end loop;
                     if Item.Has_Else
                       and then Contains_Pattern (Item.Else_Stmts)
                     then
                        return True;
                     end if;
                  when CM.Stmt_Case =>
                     for Arm of Item.Case_Arms loop
                        if Contains_Pattern (Arm.Statements) then
                           return True;
                        end if;
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     if Contains_Pattern (Item.Body_Stmts) then
                        return True;
                     end if;
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              if Contains_Pattern (Arm.Channel_Data.Statements) then
                                 return True;
                              end if;
                           when CM.Select_Arm_Delay =>
                              if Contains_Pattern (Arm.Delay_Data.Statements) then
                                 return True;
                              end if;
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;

         return False;
      end Contains_Pattern;
   begin
      return not Local_Names.Is_Empty and then Contains_Pattern (Statements);
   end Contains_Recursive_Accumulator_Pattern;

   function Uses_Structural_Traversal_Lowering
     (Subprogram : CM.Resolved_Subprogram) return Boolean
   is
      Subprogram_Name : constant String :=
        FT.Lowercase (FT.To_String (Subprogram.Name));

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean;

      function Is_Single_Return_Block
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;

      function Is_Recursive_Tail_Return
        (Statements : CM.Statement_Access_Vectors.Vector;
         Expected_Param_Name : String) return Boolean;

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Binary
           and then Operator = "="
           and then
             ((Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Left.Name) = Name
               and then Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Null)
              or else
              (Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Right.Name) = Name
               and then Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Null));
      end Is_Direct_Null_Check;

      function Is_Single_Return_Block
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
      is
      begin
         return
           Statements.Length = 1
           and then Statements (Statements.First_Index) /= null
           and then Statements (Statements.First_Index).Kind = CM.Stmt_Return
           and then Statements (Statements.First_Index).Value /= null;
      end Is_Single_Return_Block;

      function Is_Recursive_Tail_Return
        (Statements : CM.Statement_Access_Vectors.Vector;
         Expected_Param_Name : String) return Boolean
      is
         Return_Stmt : CM.Statement_Access := null;
         Call_Expr   : CM.Expr_Access := null;
      begin
         if Statements.Length /= 1 then
            return False;
         end if;

         Return_Stmt := Statements (Statements.First_Index);
         if Return_Stmt = null
           or else Return_Stmt.Kind /= CM.Stmt_Return
           or else Return_Stmt.Value = null
           or else Return_Stmt.Value.Kind /= CM.Expr_Call
         then
            return False;
         end if;

         Call_Expr := Return_Stmt.Value;
         return
           Call_Expr.Callee /= null
           and then FT.Lowercase (CM.Flatten_Name (Call_Expr.Callee)) = Subprogram_Name
           and then Call_Expr.Args.Length = Subprogram.Params.Length
           and then not Call_Expr.Args.Is_Empty
           and then Root_Name (Call_Expr.Args (Call_Expr.Args.First_Index)) = Expected_Param_Name;
      end Is_Recursive_Tail_Return;
   begin
      if Subprogram.Params.Is_Empty or else Subprogram.Statements.Is_Empty then
         return False;
      end if;

      declare
         First_Param_Name : constant String :=
           FT.To_String (Subprogram.Params (Subprogram.Params.First_Index).Name);
      begin
         if First_Param_Name'Length = 0
           or else not Is_Owner_Access
             (Subprogram.Params (Subprogram.Params.First_Index).Type_Info)
         then
            return False;
         end if;

         if Subprogram.Declarations.Is_Empty
           and then Subprogram.Params.Length = 1
           and then Subprogram.Statements.Length = 1
           and then Subprogram.Statements (Subprogram.Statements.First_Index) /= null
           and then Subprogram.Statements (Subprogram.Statements.First_Index).Kind = CM.Stmt_If
         then
            declare
               If_Stmt : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.First_Index);
            begin
               if Is_Direct_Null_Check (If_Stmt.Condition, First_Param_Name)
                 and then Is_Single_Return_Block (If_Stmt.Then_Stmts)
                 and then If_Stmt.Has_Else
                 and then Is_Recursive_Tail_Return (If_Stmt.Else_Stmts, First_Param_Name)
               then
                  for Part of If_Stmt.Elsifs loop
                     if not Is_Single_Return_Block (Part.Statements) then
                        return False;
                     end if;
                  end loop;
                  return True;
               end if;
            end;
         end if;

         if not Subprogram.Declarations.Is_Empty
           and then Subprogram.Params.Length >= 2
           and then Subprogram.Statements.Length >= 4
         then
            declare
               First_Stmt       : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.First_Index);
               Recursive_Assign : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.Last_Index - 1);
               Final_Return     : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.Last_Index);
            begin
               if First_Stmt /= null
                 and then First_Stmt.Kind = CM.Stmt_If
                 and then Is_Single_Return_Block (First_Stmt.Then_Stmts)
                 and then not First_Stmt.Has_Else
                 and then First_Stmt.Elsifs.Is_Empty
                 and then Recursive_Assign /= null
                 and then Recursive_Assign.Kind = CM.Stmt_Assign
                 and then Recursive_Assign.Value /= null
                 and then Recursive_Assign.Value.Kind = CM.Expr_Call
                 and then Recursive_Assign.Value.Callee /= null
                 and then FT.Lowercase (CM.Flatten_Name (Recursive_Assign.Value.Callee)) = Subprogram_Name
                 and then Recursive_Assign.Value.Args.Length = Subprogram.Params.Length
                 and then Root_Name (Recursive_Assign.Value.Args (Recursive_Assign.Value.Args.First_Index)) = First_Param_Name
                 and then Final_Return /= null
                 and then Final_Return.Kind = CM.Stmt_Return
                 and then Root_Name (Final_Return.Value) = Root_Name (Recursive_Assign.Target)
               then
                  return True;
               end if;
            end;
         end if;
      end;

      return False;
   end Uses_Structural_Traversal_Lowering;

   function Replace_Identifier_Token
     (Text        : String;
      Name        : String;
      Replacement : String) return String
   is
      function Is_Identifier_Char (Item : Character) return Boolean is
      begin
         return
           (Item in 'a' .. 'z')
           or else (Item in 'A' .. 'Z')
           or else (Item in '0' .. '9')
           or else Item = '_';
      end Is_Identifier_Char;

      Result : SU.Unbounded_String;
      Index  : Positive := Text'First;
   begin
      if Text'Length = 0 or else Name'Length = 0 or else Name = Replacement then
         return Text;
      end if;

      while Index <= Text'Last loop
         if Index + Name'Length - 1 <= Text'Last
           and then Text (Index .. Index + Name'Length - 1) = Name
           and then
             (Index = Text'First or else not Is_Identifier_Char (Text (Index - 1)))
           and then
             (Index + Name'Length - 1 = Text'Last
              or else not Is_Identifier_Char (Text (Index + Name'Length)))
         then
            Result := Result & SU.To_Unbounded_String (Replacement);
            Index := Index + Name'Length;
         else
            Result := Result & SU.To_Unbounded_String (String'(1 => Text (Index)));
            Index := Index + 1;
         end if;
      end loop;

      return SU.To_String (Result);
   end Replace_Identifier_Token;

   procedure Append_Gnatprove_Warning_Suppression
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Reason  : String;
      Depth   : Natural)
   is
   begin
      Append_Line
        (Buffer,
         "pragma Warnings (GNATprove, Off, """
         & Pattern
         & """, Reason => """
         & Reason
         & """);",
         Depth);
   end Append_Gnatprove_Warning_Suppression;

   procedure Append_Gnatprove_Warning_Restore
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Depth   : Natural)
   is
   begin
      Append_Line
        (Buffer,
         "pragma Warnings (GNATprove, On, """ & Pattern & """);",
         Depth);
   end Append_Gnatprove_Warning_Restore;

   procedure Append_Initialization_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Suppression
        (Buffer,
         "initialization of",
         "generated local initialization is intentional",
         Depth);
   end Append_Initialization_Warning_Suppression;

   procedure Append_Initialization_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Restore
        (Buffer,
         "initialization of",
         Depth);
   end Append_Initialization_Warning_Restore;

   procedure Append_Task_Assignment_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Suppression
        (Buffer,
         "statement has no effect",
         "task-local state updates are intentionally isolated",
         Depth);
      Append_Gnatprove_Warning_Suppression
        (Buffer,
         "unused assignment",
         "task-local state updates are intentionally isolated",
         Depth);
   end Append_Task_Assignment_Warning_Suppression;

   procedure Append_Task_Assignment_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Restore (Buffer, "unused assignment", Depth);
      Append_Gnatprove_Warning_Restore (Buffer, "statement has no effect", Depth);
   end Append_Task_Assignment_Warning_Restore;

   procedure Append_Task_If_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Suppression
        (Buffer,
         "statement has no effect",
         "task-local branching is intentionally isolated",
         Depth);
   end Append_Task_If_Warning_Suppression;

   procedure Append_Task_If_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Restore (Buffer, "statement has no effect", Depth);
   end Append_Task_If_Warning_Restore;

   procedure Append_Task_Channel_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Suppression
        (Buffer,
         "is set by",
         "channel results are consumed on the success path only",
         Depth);
   end Append_Task_Channel_Call_Warning_Suppression;

   procedure Append_Task_Channel_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural)
   is
   begin
      Append_Gnatprove_Warning_Restore (Buffer, "is set by", Depth);
   end Append_Task_Channel_Call_Warning_Restore;

   function Structural_Accumulator_Count_Total_Bound
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Count_Name : String;
      Total_Name : String;
      State      : in out Emit_State) return String
   is
      Count_Param  : constant CM.Symbol :=
        Subprogram.Params (Subprogram.Params.First_Index + 1);
      Total_Param  : constant CM.Symbol :=
        Subprogram.Params (Subprogram.Params.First_Index + 2);
      Count_Base   : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Count_Param.Type_Info);
      Total_Base   : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Total_Param.Type_Info);
      Count_High   : CM.Wide_Integer;
      Total_High   : CM.Wide_Integer;
      Step_Limit   : CM.Wide_Integer;
   begin
      if Subprogram.Params.Length < 3
        or else not Is_Integer_Type (Unit, Document, Count_Param.Type_Info)
        or else not Is_Integer_Type (Unit, Document, Total_Param.Type_Info)
        or else not Count_Base.Has_Low
        or else not Count_Base.Has_High
        or else not Total_Base.Has_Low
        or else not Total_Base.Has_High
        or else Count_Base.Low /= 0
        or else Total_Base.Low /= 0
        or else Count_Base.High <= 0
      then
         return "";
      end if;

      Count_High := CM.Wide_Integer (Count_Base.High);
      Total_High := CM.Wide_Integer (Total_Base.High);
      if Total_High < 0 or else Total_High mod Count_High /= 0 then
         return "";
      end if;

      Step_Limit := Total_High / Count_High;
      State.Needs_Safe_Runtime := True;
      return
        "Safe_Runtime.Wide_Integer ("
        & Total_Name
        & ") <= Safe_Runtime.Wide_Integer ("
        & Count_Name
        & ") * "
        & Trim_Wide_Image (Step_Limit);
   end Structural_Accumulator_Count_Total_Bound;

   procedure Append_Narrowing_Assignment
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Target     : CM.Expr_Access;
      Value      : CM.Expr_Access;
      Depth      : Natural)
   is
      Target_Name : constant String := FT.To_String (Target.Type_Name);
      Target_Image : constant String := Render_Expr (Unit, Document, Target, State);
      Wide_Image   : constant String := Render_Wide_Expr (Unit, Document, Value, State);
   begin
      Append_Line
        (Buffer,
         "pragma Assert ("
         & Wide_Image
         & " >= Safe_Runtime.Wide_Integer ("
         & Target_Name
         & "'First) and then "
         & Wide_Image
         & " <= Safe_Runtime.Wide_Integer ("
         & Target_Name
         & "'Last));",
         Depth);
      Append_Line
        (Buffer,
         Target_Image & " := " & Target_Name & " (" & Wide_Image & ");",
         Depth);

   end Append_Narrowing_Assignment;

   procedure Append_Float_Narrowing_Checks
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Target_Type  : String;
      Value_Name   : String;
      Depth        : Natural)
   is
      pragma Unreferenced (Unit, Document, Target_Type);
   begin
      Append_Line
        (Buffer,
         "pragma Assert (" & Value_Name & " = " & Value_Name & ");",
         Depth);
      Append_Line
        (Buffer,
         "pragma Assert ("
         & Value_Name
         & " >= Long_Float'First and then "
         & Value_Name
         & " <= Long_Float'Last);",
         Depth);
   end Append_Float_Narrowing_Checks;

   procedure Append_Float_Narrowing_Assignment
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Target_Type  : String;
      Target_Image : String;
      Inner_Image  : String;
      Depth        : Natural)
   is
   begin
      Append_Line (Buffer, "declare", Depth);
      Append_Line
        (Buffer,
         "Narrowed_Float_Value : constant Long_Float := Long_Float ("
         & Inner_Image
         & ");",
         Depth + 1);
      Append_Line (Buffer, "begin", Depth);
      Append_Float_Narrowing_Checks
        (Buffer,
         Unit => Unit,
         Document => Document,
         Target_Type => Target_Type,
         Value_Name => "Narrowed_Float_Value",
         Depth => Depth + 1);
      Append_Line
        (Buffer,
         Target_Image & " := " & Target_Type & " (Narrowed_Float_Value);",
         Depth + 1);
      Append_Line (Buffer, "end;", Depth);
   end Append_Float_Narrowing_Assignment;

   procedure Append_Float_Narrowing_Return
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Type : String;
      Inner_Image : String;
      Depth       : Natural)
   is
   begin
      Append_Line (Buffer, "declare", Depth);
      Append_Line
        (Buffer,
         "Narrowed_Float_Value : constant Long_Float := Long_Float ("
         & Inner_Image
         & ");",
         Depth + 1);
      Append_Line (Buffer, "begin", Depth);
      Append_Float_Narrowing_Checks
        (Buffer,
         Unit => Unit,
         Document => Document,
         Target_Type => Target_Type,
         Value_Name => "Narrowed_Float_Value",
         Depth => Depth + 1);
      Append_Line
        (Buffer,
         "return " & Target_Type & " (Narrowed_Float_Value);",
         Depth + 1);
      Append_Line (Buffer, "end;", Depth);
   end Append_Float_Narrowing_Return;

   procedure Append_Move_Null
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Value      : CM.Expr_Access;
      Depth      : Natural)
   is
      Type_Name : constant String := FT.To_String (Value.Type_Name);
      Info      : constant GM.Type_Descriptor := Lookup_Type (Unit, Document, Type_Name);
   begin
      if Has_Type (Unit, Document, Type_Name)
        and then Is_Owner_Access (Info)
        and then Value.Kind in CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index
      then
         Append_Line
           (Buffer,
            Render_Expr (Unit, Document, Value, State) & " := null;",
            Depth);
      end if;
   end Append_Move_Null;

   procedure Append_Assignment
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Stmt     : CM.Statement;
      Depth    : Natural)
   is
      Target_Type : constant String := FT.To_String (Stmt.Target.Type_Name);
      Target_Info : constant GM.Type_Descriptor :=
        (if Target_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Target_Type)
         else (others => <>));
      Target_Image : constant String := Render_Expr (Unit, Document, Stmt.Target, State);
      Value_Image  : constant String :=
        Render_Expr_For_Target_Type (Unit, Document, Stmt.Value, Target_Info, State);
      Needs_Target_Snapshot : constant Boolean :=
        Stmt.Target /= null
        and then Stmt.Target.Kind = CM.Expr_Select
        and then Target_Image'Length > 0
        and then Value_Image'Length > 0
        and then Expr_Contains_Target (Stmt.Value, Stmt.Target);
   begin
      if Needs_Target_Snapshot then
         declare
            Snapshot_Name : constant String :=
              Root_Name (Stmt.Target) & "_" & FT.To_String (Stmt.Target.Selector) & "_Snapshot";
            Snapshot_Type : constant String :=
              Render_Type_Name (Unit, Document, FT.To_String (Stmt.Target.Type_Name));
            Snapshot_Supported   : Boolean := True;
            Snapshot_Value_Image : constant String :=
              Render_Expr_With_Target_Substitution
                (Unit,
                 Document,
                 Stmt.Value,
                 Stmt.Target,
                 Snapshot_Name,
                 State,
                 Snapshot_Supported);
         begin
            if not Snapshot_Supported or else Snapshot_Value_Image'Length = 0 then
               Raise_Unsupported
                 (State,
                  Stmt.Span,
                  "target-snapshot substitution shape is not yet supported in Ada emission");
            end if;

            Append_Line (Buffer, "declare", Depth);
            Append_Line
              (Buffer,
               Snapshot_Name & " : constant " & Snapshot_Type & " := " & Target_Image & ";",
               Depth + 1);
            Append_Line (Buffer, "begin", Depth);
            if Is_Integer_Type (Unit, Document, Target_Type)
              and then Uses_Wide_Value (Unit, Document, State, Stmt.Value)
            then
               declare
                  Snapshot_Wide_Supported : Boolean := True;
                  Snapshot_Wide_Image : constant String :=
                    Render_Wide_Expr_With_Target_Substitution
                      (Unit,
                       Document,
                       Stmt.Value,
                       Stmt.Target,
                       Snapshot_Name,
                       State,
                       Snapshot_Wide_Supported);
               begin
                  if not Snapshot_Wide_Supported or else Snapshot_Wide_Image'Length = 0 then
                     Raise_Unsupported
                       (State,
                        Stmt.Span,
                        "wide target-snapshot substitution shape is not yet supported in Ada emission");
                  end if;

                  Append_Line
                    (Buffer,
                     "pragma Assert ("
                     & Snapshot_Wide_Image
                     & " >= Safe_Runtime.Wide_Integer ("
                     & Target_Type
                     & "'First) and then "
                     & Snapshot_Wide_Image
                     & " <= Safe_Runtime.Wide_Integer ("
                     & Target_Type
                     & "'Last));",
                     Depth + 1);
                  Append_Line
                    (Buffer,
                     Target_Image & " := " & Target_Type & " (" & Snapshot_Wide_Image & ");",
                     Depth + 1);
               end;
            elsif Is_Explicit_Float_Narrowing (Unit, Document, Target_Type, Stmt.Value)
            then
               declare
                  Snapshot_Float_Supported : Boolean := True;
                  Snapshot_Inner_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit,
                       Document,
                       Stmt.Value.Inner,
                       Stmt.Target,
                       Snapshot_Name,
                       State,
                       Snapshot_Float_Supported);
               begin
                  if not Snapshot_Float_Supported or else Snapshot_Inner_Image'Length = 0 then
                     Raise_Unsupported
                       (State,
                        Stmt.Span,
                        "float target-snapshot substitution shape is not yet supported in Ada emission");
                  end if;

                  Append_Float_Narrowing_Assignment
                    (Buffer,
                     Unit => Unit,
                     Document => Document,
                     Target_Type => Target_Type,
                     Target_Image => Target_Image,
                     Inner_Image => Snapshot_Inner_Image,
                     Depth => Depth + 1);
               end;
            else
               Append_Line
                 (Buffer,
                  Target_Image & " := " & Snapshot_Value_Image & ";",
                  Depth + 1);
            end if;
            Append_Line (Buffer, "end;", Depth);
         end;
      elsif Stmt.Target.Kind = CM.Expr_Ident
        and then Is_Wide_Name (State, FT.To_String (Stmt.Target.Name))
      then
         Append_Line
           (Buffer,
            Target_Image & " := " & Render_Wide_Expr (Unit, Document, Stmt.Value, State) & ";",
            Depth);
      elsif Is_Integer_Type (Unit, Document, Target_Type)
        and then Uses_Wide_Value (Unit, Document, State, Stmt.Value)
      then
         Append_Narrowing_Assignment
           (Buffer, Unit, Document, State, Stmt.Target, Stmt.Value, Depth);
      else
         declare
            Condition_Image : FT.UString;
            Lower_Image     : FT.UString;
            Upper_Image     : FT.UString;
         begin
            if Is_Float_Type (Unit, Document, Target_Type)
              and then Try_Render_Stable_Float_Interpolation
                (Unit,
                 Document,
                 Stmt.Value,
                 State,
                 Condition_Image,
                 Lower_Image,
                 Upper_Image)
            then
               Append_Line
                 (Buffer,
                  "if " & FT.To_String (Condition_Image) & " then",
                  Depth);
               Append_Line
                 (Buffer,
                  Target_Image & " := " & FT.To_String (Lower_Image) & ";",
                  Depth + 1);
               Append_Line (Buffer, "else", Depth);
               Append_Line
                 (Buffer,
                  Target_Image & " := " & FT.To_String (Upper_Image) & ";",
                  Depth + 1);
               Append_Line (Buffer, "end if;", Depth);
            elsif Is_Explicit_Float_Narrowing (Unit, Document, Target_Type, Stmt.Value) then
               Append_Float_Narrowing_Assignment
                 (Buffer,
                  Unit => Unit,
                  Document => Document,
                  Target_Type => Target_Type,
                  Target_Image => Target_Image,
                  Inner_Image => Render_Expr (Unit, Document, Stmt.Value.Inner, State),
                  Depth => Depth);
            else
               Append_Line (Buffer, Target_Image & " := " & Value_Image & ";", Depth);
            end if;
         end;
      end if;

      if Is_Owner_Access (Target_Info)
        and then not
          (Stmt.Target /= null
           and then Stmt.Target.Kind = CM.Expr_Ident
           and then Root_Name (Stmt.Value) = FT.To_String (Stmt.Target.Name))
      then
         Append_Move_Null (Buffer, Unit, Document, State, Stmt.Value, Depth);
      end if;
   end Append_Assignment;

   procedure Append_Float_Loop_Invariant
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Target   : CM.Expr_Access;
      Depth    : Natural)
   is
      pragma Unreferenced (State);
   begin
      if Target = null
        or else Target.Kind /= CM.Expr_Ident
        or else not Has_Text (Target.Type_Name)
        or else not Has_Type (Unit, Document, FT.To_String (Target.Type_Name))
      then
         return;
      end if;

      declare
         Target_Type : constant String := FT.To_String (Target.Type_Name);
         Target_Info : constant GM.Type_Descriptor := Lookup_Type (Unit, Document, Target_Type);
      begin
         if not Is_Float_Type (Unit, Document, Target_Type) then
            return;
         end if;

         Append_Line
           (Buffer,
            "pragma Loop_Invariant ("
            & FT.To_String (Target.Name)
            & " >= "
            & Render_Type_Name (Target_Info)
            & "'First and then "
            & FT.To_String (Target.Name)
            & " <= "
            & Render_Type_Name (Target_Info)
            & "'Last);",
            Depth);
      end;
   end Append_Float_Loop_Invariant;

   procedure Append_Integer_Loop_Invariant
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Target   : CM.Expr_Access;
      Depth    : Natural)
   is
   begin
      if Target = null
        or else Target.Kind /= CM.Expr_Ident
        or else not Has_Text (Target.Type_Name)
        or else not Is_Wide_Name (State, FT.To_String (Target.Name))
      then
         return;
      end if;

      declare
         Target_Type : constant String := FT.To_String (Target.Type_Name);
      begin
         if not Is_Integer_Type (Unit, Document, Target_Type)
           or else not Is_Builtin_Integer_Name (Target_Type)
         then
            return;
         end if;

         Append_Line
           (Buffer,
            "pragma Loop_Invariant ("
            & FT.To_String (Target.Name)
            & " >= Safe_Runtime.Wide_Integer ("
            & Target_Type
            & "'First) and then "
            & FT.To_String (Target.Name)
            & " <= Safe_Runtime.Wide_Integer ("
            & Target_Type
            & "'Last));",
            Depth);
      end;
   end Append_Integer_Loop_Invariant;

   procedure Append_Return
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Value      : CM.Expr_Access;
      Return_Type : String;
      Depth      : Natural)
   is
      Return_Info : constant GM.Type_Descriptor :=
        (if Return_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Return_Type)
         else (others => <>));
   begin
      if Value = null then
         if Return_Type'Length > 0 then
            Raise_Internal ("function return missing value during Ada emission");
         end if;
         Append_Line (Buffer, "return;", Depth);
      elsif Is_Explicit_Float_Narrowing (Unit, Document, Return_Type, Value) then
         Append_Float_Narrowing_Return
           (Buffer,
            Unit => Unit,
            Document => Document,
            Target_Type => Return_Type,
            Inner_Image => Render_Expr (Unit, Document, Value.Inner, State),
            Depth => Depth);
      elsif Return_Type'Length > 0
        and then Is_Integer_Type (Unit, Document, Return_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         declare
            Wide_Image : constant String := Render_Wide_Expr (Unit, Document, Value, State);
         begin
            Append_Line
              (Buffer,
               "pragma Assert ("
               & Wide_Image
               & " >= Safe_Runtime.Wide_Integer ("
               & Return_Type
               & "'First) and then "
               & Wide_Image
               & " <= Safe_Runtime.Wide_Integer ("
               & Return_Type
               & "'Last));",
               Depth);
            Append_Line
              (Buffer,
               "return " & Return_Type & " (" & Wide_Image & ");",
               Depth);
         end;
      else
         Append_Line
           (Buffer,
           "return "
           & (if Return_Type'Length > 0
               and then Is_Owner_Access (Return_Info)
              then
                Render_Expr_For_Target_Type
                  (Unit, Document, Value, Return_Info, State)
              elsif Return_Type'Length > 0
               and then Is_Bounded_String_Type (Return_Info)
              then
                Render_Expr_For_Target_Type
                  (Unit, Document, Value, Return_Info, State)
              elsif Return_Type'Length > 0
                and then Value.Kind = CM.Expr_Aggregate
                and then not Return_Info.Discriminant_Constraints.Is_Empty
              then
                Return_Type
                & "'"
                & Render_Record_Aggregate_For_Type
                    (Unit, Document, Value, Return_Info, State)
              elsif Return_Type'Length > 0
                and then Value.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
              then Return_Type & "'" & Render_Expr (Unit, Document, Value, State)
              elsif Return_Type'Length > 0 and then Has_Text (Return_Info.Name)
              then
                Render_Expr_For_Target_Type
                  (Unit, Document, Value, Return_Info, State)
              else Render_Expr (Unit, Document, Value, State))
           & ";",
           Depth);
      end if;
   end Append_Return;

   procedure Append_Return_With_Cleanup
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Value       : CM.Expr_Access;
      Return_Type : String;
      Depth       : Natural)
   is
      Value_Type : constant String := FT.To_String (Value.Type_Name);
      Value_Info : constant GM.Type_Descriptor :=
        (if Value_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Value_Type)
         else (others => <>));
      Return_Info : constant GM.Type_Descriptor :=
        (if Return_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Return_Type)
         else (others => <>));
      Needs_Move_Null : constant Boolean :=
        Value_Type'Length > 0
        and then Is_Owner_Access (Value_Info)
        and then Value.Kind in CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index;
      Returned_Name : constant String := Root_Name (Value);
      Can_Skip_Cleanup : constant Boolean :=
        Needs_Move_Null
        and then Value.Kind = CM.Expr_Ident
        and then Returned_Name'Length > 0;
   begin
      if Return_Type'Length = 0 then
         Raise_Internal ("cleanup-preserving return requires a function return type");
      end if;

      Append_Line (Buffer, "declare", Depth);
      if Is_Explicit_Float_Narrowing (Unit, Document, Return_Type, Value) then
         Append_Line
           (Buffer,
            "Narrowed_Float_Value : constant Long_Float := Long_Float ("
            & Render_Expr (Unit, Document, Value.Inner, State)
            & ");",
            Depth + 1);
         Append_Line (Buffer, "Return_Value : " & Return_Type & ";", Depth + 1);
      elsif Is_Integer_Type (Unit, Document, Return_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         declare
            Wide_Image : constant String := Render_Wide_Expr (Unit, Document, Value, State);
         begin
            Append_Line
              (Buffer,
               "Wide_Return_Value : constant Safe_Runtime.Wide_Integer := "
               & Wide_Image
               & ";",
               Depth + 1);
            Append_Line (Buffer, "Return_Value : " & Return_Type & ";", Depth + 1);
         end;
      else
         Append_Line
           (Buffer,
            "Return_Value : constant "
            & Return_Type
            & " := "
            & Render_Expr_For_Target_Type (Unit, Document, Value, Return_Info, State)
            & ";",
            Depth + 1);
      end if;
      Append_Line (Buffer, "begin", Depth);
      if Is_Explicit_Float_Narrowing (Unit, Document, Return_Type, Value) then
         Append_Float_Narrowing_Checks
           (Buffer,
            Unit => Unit,
            Document => Document,
            Target_Type => Return_Type,
            Value_Name => "Narrowed_Float_Value",
            Depth => Depth + 1);
         Append_Line
           (Buffer,
            "Return_Value := " & Return_Type & " (Narrowed_Float_Value);",
            Depth + 1);
      elsif Is_Integer_Type (Unit, Document, Return_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         Append_Line
           (Buffer,
            "pragma Assert ("
            & "Wide_Return_Value >= Safe_Runtime.Wide_Integer ("
            & Return_Type
            & "'First) and then "
            & "Wide_Return_Value <= Safe_Runtime.Wide_Integer ("
            & Return_Type
            & "'Last));",
            Depth + 1);
         Append_Line
           (Buffer,
            "Return_Value := " & Return_Type & " (Wide_Return_Value);",
            Depth + 1);
      end if;
      if Needs_Move_Null and then not Can_Skip_Cleanup then
         Append_Move_Null (Buffer, Unit, Document, State, Value, Depth + 1);
      end if;
      Render_Active_Cleanup
        (Buffer,
         State,
         Depth + 1,
         Skip_Name => (if Can_Skip_Cleanup then Returned_Name else ""));
      Append_Line (Buffer, "return Return_Value;", Depth + 1);
      Append_Line (Buffer, "end;", Depth);
   end Append_Return_With_Cleanup;

   procedure Render_Block_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      State        : in out Emit_State;
      Depth        : Natural)
   is
   begin
      for Decl of Declarations loop
         Append_Line
           (Buffer,
            Render_Object_Decl_Text (Unit, Document, State, Decl, Local_Context => True),
            Depth);
         if Is_Owner_Access (Decl.Type_Info) then
            State.Needs_Unchecked_Deallocation := True;
         end if;
      end loop;
   end Render_Block_Declarations;

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural) is
   begin
      if Declarations.Is_Empty then
         return;
      end if;
      for Reverse_Index in reverse Declarations.First_Index .. Declarations.Last_Index loop
         declare
            Decl : constant CM.Resolved_Object_Decl := Declarations (Reverse_Index);
         begin
            if Is_Owner_Access (Decl.Type_Info) then
               for Name of Decl.Names loop
                  Render_Cleanup_Item
                     (Buffer,
                      (Action    => Cleanup_Deallocate,
                       Name      => Name,
                       Type_Name => Decl.Type_Info.Name,
                       Free_Proc => FT.To_UString (""),
                       Is_Constant => False),
                      Depth);
               end loop;
            end if;
         end;
      end loop;
   end Render_Cleanup;

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural) is
   begin
      if Declarations.Is_Empty then
         return;
      end if;
      for Reverse_Index in reverse Declarations.First_Index .. Declarations.Last_Index loop
         declare
            Decl : constant CM.Object_Decl := Declarations (Reverse_Index);
         begin
            if Is_Owner_Access (Decl.Type_Info) then
               for Name of Decl.Names loop
                  Render_Cleanup_Item
                     (Buffer,
                      (Action    => Cleanup_Deallocate,
                       Name      => Name,
                       Type_Name => Decl.Type_Info.Name,
                       Free_Proc => FT.To_UString (""),
                       Is_Constant => False),
                      Depth);
               end loop;
            end if;
         end;
      end loop;
   end Render_Cleanup;

   procedure Render_Statements
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False)
   is
      function Tail_Statements
        (First : Positive) return CM.Statement_Access_Vectors.Vector
      is
         Result : CM.Statement_Access_Vectors.Vector;
      begin
         if Statements.Is_Empty or else First > Statements.Last_Index then
            return Result;
         end if;
         for Index in First .. Statements.Last_Index loop
            Result.Append (Statements (Index));
         end loop;
         return Result;
      end Tail_Statements;
   begin
      if Statements.Is_Empty then
         return;
      end if;

      for Index in Statements.First_Index .. Statements.Last_Index loop
         declare
            Item : constant CM.Statement_Access := Statements (Index);
         begin
            if Item = null then
               Raise_Unsupported
                 (State,
                  FT.Null_Span,
                  "encountered null statement during Ada emission");
            end if;

            case Item.Kind is
            when CM.Stmt_Object_Decl =>
               declare
                  Tail                : constant CM.Statement_Access_Vectors.Vector :=
                    Tail_Statements (Index + 1);
                  Previous_Wide_Count : constant Ada.Containers.Count_Type :=
                    State.Wide_Local_Names.Length;
                  Block_Declarations  : CM.Object_Decl_Vectors.Vector;
               begin
                  Block_Declarations.Append (Item.Decl);
                  Collect_Wide_Locals
                    (Unit,
                     Document,
                     State,
                     Block_Declarations,
                     Tail);
                  Push_Type_Binding_Frame (State);
                  Register_Type_Bindings (State, Block_Declarations);
                  Push_Cleanup_Frame (State);
                  Register_Cleanup_Items (State, Block_Declarations);
                  Append_Line (Buffer, "declare", Depth);
                  if State.Task_Body_Depth > 0 then
                     Append_Initialization_Warning_Suppression
                       (Buffer, Depth + 1);
                  end if;
                  Append_Line
                    (Buffer,
                     Render_Object_Decl_Text (Unit, Document, State, Item.Decl, Local_Context => True),
                     Depth + 1);
                  if State.Task_Body_Depth > 0 then
                     Append_Initialization_Warning_Restore
                       (Buffer, Depth + 1);
                  end if;
                  Render_Free_Declarations (Buffer, Block_Declarations, Depth + 1);
                  Append_Line (Buffer, "begin", Depth);
                  Render_Required_Statement_Suite
                    (Buffer,
                     Unit,
                     Document,
                     Tail,
                     State,
                     Depth + 1,
                     Return_Type,
                     In_Loop);
                  if Tail.Is_Empty or else Statements_Fall_Through (Tail) then
                     Render_Cleanup (Buffer, Block_Declarations, Depth + 1);
                  end if;
                  Append_Line (Buffer, "end;", Depth);
                  Pop_Cleanup_Frame (State);
                  Pop_Type_Binding_Frame (State);
                  Restore_Wide_Names (State, Previous_Wide_Count);
               end;
               return;
            when CM.Stmt_Destructure_Decl =>
               declare
                  Tail                : constant CM.Statement_Access_Vectors.Vector :=
                    Tail_Statements (Index + 1);
                  Previous_Wide_Count : constant Ada.Containers.Count_Type :=
                    State.Wide_Local_Names.Length;
                  Empty_Declarations  : CM.Object_Decl_Vectors.Vector;
                  Tuple_Type          : constant GM.Type_Descriptor :=
                    Base_Type (Unit, Document, Item.Destructure.Type_Info);
                  Temp_Name           : constant String :=
                    "Safe_Destructure_"
                    & Ada.Strings.Fixed.Trim (Natural'Image (Index), Ada.Strings.Both);
               begin
                  Collect_Wide_Locals
                    (Unit,
                     Document,
                     State,
                     Empty_Declarations,
                     Tail_Statements (Index));
                  Push_Type_Binding_Frame (State);
                  Push_Cleanup_Frame (State);
                  Append_Line (Buffer, "declare", Depth);
                  Append_Line
                    (Buffer,
                     Temp_Name
                     & " : "
                     & Render_Type_Name (Item.Destructure.Type_Info)
                     & " := "
                     & Render_Expr
                         (Unit,
                          Document,
                          Item.Destructure.Initializer,
                          State)
                     & ";",
                     Depth + 1);
                  for Tuple_Index in Item.Destructure.Names.First_Index .. Item.Destructure.Names.Last_Index loop
                     Append_Line
                        (Buffer,
                         FT.To_String (Item.Destructure.Names (Tuple_Index))
                         & " : "
                         & Render_Type_Name
                             (Unit,
                             Document,
                             FT.To_String (Tuple_Type.Tuple_Element_Types (Tuple_Index)))
                        & " := "
                        & Temp_Name
                             & "."
                             & Tuple_Field_Name (Positive (Tuple_Index))
                             & ";",
                        Depth + 1);
                     declare
                        Element_Type : GM.Type_Descriptor;
                     begin
                        if Type_Info_From_Name
                             (Unit,
                              Document,
                              FT.To_String (Tuple_Type.Tuple_Element_Types (Tuple_Index)),
                              Element_Type)
                        then
                           Add_Type_Binding
                             (State,
                              FT.To_String (Item.Destructure.Names (Tuple_Index)),
                              Element_Type);
                        end if;
                     end;
                  end loop;
                  Append_Line (Buffer, "begin", Depth);
                  Render_Required_Statement_Suite
                    (Buffer,
                     Unit,
                     Document,
                     Tail,
                     State,
                     Depth + 1,
                     Return_Type,
                     In_Loop);
                  Append_Line (Buffer, "end;", Depth);
                  Pop_Cleanup_Frame (State);
                  Pop_Type_Binding_Frame (State);
                  Restore_Wide_Names (State, Previous_Wide_Count);
               end;
               return;
            when CM.Stmt_Assign =>
               if State.Task_Body_Depth > 0 then
                  Append_Task_Assignment_Warning_Suppression (Buffer, Depth);
               end if;
               Append_Assignment (Buffer, Unit, Document, State, Item.all, Depth);
               if In_Loop then
                  Append_Integer_Loop_Invariant
                    (Buffer, Unit, Document, State, Item.Target, Depth);
                  Append_Float_Loop_Invariant
                    (Buffer, Unit, Document, State, Item.Target, Depth);
               end if;
               if State.Task_Body_Depth > 0 then
                  Append_Task_Assignment_Warning_Restore (Buffer, Depth);
               end if;
            when CM.Stmt_Call =>
               if Is_Print_Call (Item.Call) then
                  State.Needs_Safe_IO := True;
                  Append_Line
                    (Buffer,
                     Safe_IO_Unit_Name (FT.To_String (Unit.Package_Name))
                     & ".Put_Line ("
                     & Render_Print_Argument
                         (Unit,
                          Document,
                          Item.Call.Args (Item.Call.Args.First_Index),
                          State)
                     & ");",
                     Depth);
               else
                  Append_Line
                    (Buffer,
                     Render_Expr (Unit, Document, Item.Call, State) & ";",
                     Depth);
               end if;
            when CM.Stmt_Return =>
               if Item.Value /= null and then Has_Active_Cleanup_Items (State) then
                  Append_Return_With_Cleanup
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Item.Value,
                     Return_Type,
                     Depth);
               else
                  Render_Active_Cleanup (Buffer, State, Depth);
                  Append_Return
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Item.Value,
                     Return_Type,
                     Depth);
               end if;
            when CM.Stmt_If =>
               if State.Task_Body_Depth > 0 then
                  Append_Task_If_Warning_Suppression (Buffer, Depth);
               end if;
               Append_Line
                 (Buffer,
                  "if " & Render_Expr (Unit, Document, Item.Condition, State) & " then",
                  Depth);
               Render_Required_Statement_Suite
                 (Buffer, Unit, Document, Item.Then_Stmts, State, Depth + 1, Return_Type, In_Loop);
               for Part of Item.Elsifs loop
                  Append_Line
                    (Buffer,
                     "elsif " & Render_Expr (Unit, Document, Part.Condition, State) & " then",
                     Depth);
                  Render_Required_Statement_Suite
                    (Buffer, Unit, Document, Part.Statements, State, Depth + 1, Return_Type, In_Loop);
               end loop;
               if Item.Has_Else then
                  Append_Line (Buffer, "else", Depth);
                  Render_Required_Statement_Suite
                    (Buffer, Unit, Document, Item.Else_Stmts, State, Depth + 1, Return_Type, In_Loop);
               end if;
               Append_Line (Buffer, "end if;", Depth);
               if State.Task_Body_Depth > 0 then
                  Append_Task_If_Warning_Restore (Buffer, Depth);
               end if;
            when CM.Stmt_Case =>
               declare
                  Case_Info : constant GM.Type_Descriptor :=
                    Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Item.Case_Expr));
               begin
                  if FT.Lowercase (FT.To_String (Case_Info.Kind)) = "string" then
                     declare
                        Case_Name : constant String :=
                          "Safe_String_Case_Expr_"
                          & Ada.Strings.Fixed.Trim (Positive'Image (Positive (Index)), Ada.Strings.Both);
                        First_String_Arm : Boolean := True;
                     begin
                        Append_Line (Buffer, "declare", Depth);
                        Append_Line
                          (Buffer,
                           Case_Name
                           & " : constant String := "
                           & Render_String_Expr (Unit, Document, Item.Case_Expr, State)
                           & ";",
                           Depth + 1);
                        Append_Line (Buffer, "begin", Depth);
                        for Arm of Item.Case_Arms loop
                           if Arm.Is_Others then
                              if First_String_Arm then
                                 Append_Line (Buffer, "if True then", Depth + 1);
                                 First_String_Arm := False;
                              else
                                 Append_Line (Buffer, "else", Depth + 1);
                              end if;
                           elsif First_String_Arm then
                              Append_Line
                                (Buffer,
                                 "if "
                                 & Case_Name
                                 & " = "
                                 & Render_String_Expr (Unit, Document, Arm.Choice, State)
                                 & " then",
                                 Depth + 1);
                              First_String_Arm := False;
                           else
                              Append_Line
                                (Buffer,
                                 "elsif "
                                 & Case_Name
                                 & " = "
                                 & Render_String_Expr (Unit, Document, Arm.Choice, State)
                                 & " then",
                                 Depth + 1);
                           end if;
                           Render_Required_Statement_Suite
                             (Buffer,
                              Unit,
                              Document,
                              Arm.Statements,
                              State,
                              Depth + 2,
                              Return_Type,
                              In_Loop);
                        end loop;
                        Append_Line (Buffer, "end if;", Depth + 1);
                        Append_Line (Buffer, "end;", Depth);
                     end;
                  else
                     Append_Line
                       (Buffer,
                        "case " & Render_Expr (Unit, Document, Item.Case_Expr, State) & " is",
                        Depth);
                     for Arm of Item.Case_Arms loop
                        Append_Line
                          (Buffer,
                           (if Arm.Is_Others
                            then "when others =>"
                            else "when " & Render_Expr (Unit, Document, Arm.Choice, State) & " =>"),
                           Depth + 1);
                        Render_Required_Statement_Suite
                          (Buffer,
                           Unit,
                           Document,
                           Arm.Statements,
                           State,
                           Depth + 2,
                           Return_Type,
                           In_Loop);
                     end loop;
                     Append_Line (Buffer, "end case;", Depth);
                  end if;
               end;
            when CM.Stmt_While =>
               Append_Line
                 (Buffer,
                  "while " & Render_Expr (Unit, Document, Item.Condition, State) & " loop",
                  Depth);
               declare
                  Variant_Image : constant String := Loop_Variant_Image (Unit, Document, Item.Condition, State);
               begin
                  if Variant_Image'Length > 0 then
                     Append_Line (Buffer, "pragma Loop_Variant (" & Variant_Image & ");", Depth + 1);
                  end if;
               end;
               Render_Required_Statement_Suite
                 (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
               Append_Line (Buffer, "end loop;", Depth);
            when CM.Stmt_For =>
               if Item.Loop_Iterable /= null then
                  declare
                     Iterable_Info : constant GM.Type_Descriptor :=
                       Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Item.Loop_Iterable));
                     Is_String_Iterable : constant Boolean :=
                       FT.Lowercase (FT.To_String (Iterable_Info.Kind)) = "string";
                     function One_Char_String_Info return GM.Type_Descriptor is
                        Found : Boolean := False;
                     begin
                        return Synthetic_Bounded_String_Type ("__bounded_string_1", Found);
                     end One_Char_String_Info;
                     Element_Info  : constant GM.Type_Descriptor :=
                       (if Is_String_Iterable
                        then One_Char_String_Info
                        else Resolve_Type_Name
                               (Unit,
                                Document,
                                FT.To_String (Iterable_Info.Component_Type)));
                     Snapshot_Name : constant String :=
                       "Safe_For_Of_Snapshot_"
                       & Ada.Strings.Fixed.Trim (Positive'Image (Positive (Index)), Ada.Strings.Both);
                     Index_Name    : constant String :=
                       "Safe_For_Of_Index_"
                       & Ada.Strings.Fixed.Trim (Positive'Image (Positive (Index)), Ada.Strings.Both);
                     Snapshot_Init : constant String :=
                       (if Is_String_Iterable
                           and then Is_Plain_String_Type (Unit, Document, Iterable_Info)
                        then
                          "Safe_String_RT.Clone ("
                          & Render_Expr (Unit, Document, Item.Loop_Iterable, State)
                          & ")"
                        elsif Iterable_Info.Growable
                        then
                          Array_Runtime_Instance_Name (Iterable_Info)
                          & ".Clone ("
                          & Render_Expr (Unit, Document, Item.Loop_Iterable, State)
                          & ")"
                        else Render_Expr (Unit, Document, Item.Loop_Iterable, State));
                     Snapshot_Type_Image : constant String :=
                       Render_Type_Name (Iterable_Info);
                     Element_Type_Image  : constant String :=
                       Render_Type_Name (Element_Info);
                  begin
                     if not Is_String_Iterable
                       and then Has_Heap_Value_Type (Unit, Document, Element_Info)
                       and then not Is_Plain_String_Type (Unit, Document, Element_Info)
                       and then not Is_Growable_Array_Type (Unit, Document, Element_Info)
                     then
                        Raise_Unsupported
                          (State,
                           Item.Span,
                           "`for ... of` over arrays with composite heap-backed elements is not yet supported in Ada emission");
                     end if;

                     if Is_String_Iterable
                       and then Is_Plain_String_Type (Unit, Document, Iterable_Info)
                     then
                        State.Needs_Safe_String_RT := True;
                     elsif Iterable_Info.Growable then
                        State.Needs_Safe_Array_RT := True;
                     end if;
                     if Is_String_Iterable then
                        Register_Bounded_String_Type (State, Element_Info);
                        if Is_Bounded_String_Type (Iterable_Info) then
                           Register_Bounded_String_Type (State, Iterable_Info);
                        end if;
                     end if;

                     Push_Cleanup_Frame (State);
                     if Is_String_Iterable
                       and then Is_Plain_String_Type (Unit, Document, Iterable_Info)
                     then
                        Add_Cleanup_Item
                          (State,
                           Snapshot_Name,
                           Snapshot_Type_Image,
                           "Safe_String_RT.Free",
                           Is_Constant => True);
                     elsif Iterable_Info.Growable then
                        Add_Cleanup_Item
                          (State,
                           Snapshot_Name,
                           Snapshot_Type_Image,
                           Array_Runtime_Instance_Name (Iterable_Info) & ".Free",
                           Is_Constant => True);
                     end if;

                     Append_Line (Buffer, "declare", Depth);
                     Append_Line
                       (Buffer,
                        Snapshot_Name & " : constant " & Snapshot_Type_Image & " := " & Snapshot_Init & ";",
                        Depth + 1);
                     Append_Line (Buffer, "begin", Depth);

                     if Is_String_Iterable then
                        Append_Line
                          (Buffer,
                           "for " & Index_Name & " in 1 .. Integer ("
                           & (if Is_Bounded_String_Type (Iterable_Info)
                              then
                                Bounded_String_Instance_Name (Iterable_Info)
                                & ".Length ("
                                & Snapshot_Name
                                & ")"
                              else
                                "Safe_String_RT.Length ("
                                & Snapshot_Name
                                & ")")
                           & ") loop",
                           Depth + 1);
                     elsif Iterable_Info.Growable then
                        Append_Line
                          (Buffer,
                           "for " & Index_Name & " in 1 .. Long_Long_Integer ("
                           & Array_Runtime_Instance_Name (Iterable_Info)
                           & ".Length ("
                           & Snapshot_Name
                           & ")) loop",
                           Depth + 1);
                     else
                        Append_Line
                          (Buffer,
                           "for " & Index_Name & " in " & Snapshot_Name & "'Range loop",
                           Depth + 1);
                     end if;

                     declare
                        Loop_Item_Init : SU.Unbounded_String := SU.Null_Unbounded_String;
                        Fixed_Element_Image : constant String :=
                          Snapshot_Name & " (" & Index_Name & ")";
                     begin
                        if Is_String_Iterable then
                           Loop_Item_Init :=
                             SU.To_Unbounded_String
                               (Bounded_String_Instance_Name (Element_Info)
                                & ".To_Bounded ("
                                & (if Is_Bounded_String_Type (Iterable_Info)
                                   then
                                     Bounded_String_Instance_Name (Iterable_Info)
                                     & ".To_String ("
                                     & Snapshot_Name
                                     & ")"
                                   else
                                     "Safe_String_RT.To_String ("
                                     & Snapshot_Name
                                     & ")")
                                & " ("
                                & Index_Name
                                & " .. "
                                & Index_Name
                                & "))");
                        elsif Iterable_Info.Growable then
                           Loop_Item_Init :=
                             SU.To_Unbounded_String
                               (Array_Runtime_Instance_Name (Iterable_Info)
                                & ".Element ("
                                & Snapshot_Name
                                & ", Positive ("
                                & Index_Name
                                & "))");
                        elsif Is_Plain_String_Type (Unit, Document, Element_Info) then
                           State.Needs_Safe_String_RT := True;
                           Loop_Item_Init :=
                             SU.To_Unbounded_String
                               ("Safe_String_RT.Clone ("
                                & Fixed_Element_Image
                                & ")");
                        elsif Is_Growable_Array_Type (Unit, Document, Element_Info) then
                           State.Needs_Safe_Array_RT := True;
                           Loop_Item_Init :=
                             SU.To_Unbounded_String
                               (Array_Runtime_Instance_Name (Element_Info)
                                & ".Clone ("
                                & Fixed_Element_Image
                                & ")");
                        else
                           Loop_Item_Init := SU.To_Unbounded_String (Fixed_Element_Image);
                        end if;

                        Push_Cleanup_Frame (State);
                        if Is_Plain_String_Type (Unit, Document, Element_Info) then
                           Add_Cleanup_Item
                             (State,
                              FT.To_String (Item.Loop_Var),
                              Element_Type_Image,
                              "Safe_String_RT.Free");
                        elsif Is_Growable_Array_Type (Unit, Document, Element_Info) then
                           Add_Cleanup_Item
                             (State,
                              FT.To_String (Item.Loop_Var),
                              Element_Type_Image,
                              Array_Runtime_Instance_Name (Element_Info) & ".Free");
                        end if;

                        Append_Line (Buffer, "declare", Depth + 2);
                        Append_Line
                          (Buffer,
                           FT.To_String (Item.Loop_Var)
                           & " : "
                           & Element_Type_Image
                           & " := "
                           & SU.To_String (Loop_Item_Init)
                           & ";",
                           Depth + 3);
                        Append_Line (Buffer, "begin", Depth + 2);
                        Render_Required_Statement_Suite
                          (Buffer,
                           Unit,
                           Document,
                           Item.Body_Stmts,
                           State,
                           Depth + 3,
                           Return_Type,
                           True);
                        if Statements_Fall_Through (Item.Body_Stmts) then
                           Render_Current_Cleanup_Frame (Buffer, State, Depth + 3);
                        end if;
                        Append_Line (Buffer, "end;", Depth + 2);
                        Pop_Cleanup_Frame (State);
                     end;

                     Append_Line (Buffer, "end loop;", Depth + 1);
                     Render_Current_Cleanup_Frame (Buffer, State, Depth + 1);
                     Append_Line (Buffer, "end;", Depth);
                     Pop_Cleanup_Frame (State);
                  end;
               else
                  Append_Line
                    (Buffer,
                     "for "
                     & FT.To_String (Item.Loop_Var)
                     & " in "
                     & Render_Discrete_Range (Unit, Document, Item.Loop_Range, State)
                     & " loop",
                     Depth);
                  Render_Required_Statement_Suite
                    (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
                  Append_Line (Buffer, "end loop;", Depth);
               end if;
            when CM.Stmt_Loop =>
               Append_Line (Buffer, "loop", Depth);
               Render_Required_Statement_Suite
                 (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
               Append_Line (Buffer, "end loop;", Depth);
            when CM.Stmt_Exit =>
               if Item.Condition /= null then
                  Append_Line
                    (Buffer,
                     "exit when " & Render_Expr (Unit, Document, Item.Condition, State) & ";",
                     Depth);
               else
                  Append_Line (Buffer, "exit;", Depth);
               end if;
            when CM.Stmt_Send =>
               State.Needs_Gnat_Adc := True;
               Append_Line
                 (Buffer,
                  Render_Expr (Unit, Document, Item.Channel_Name, State)
                  & ".Send ("
                  & Render_Channel_Send_Value
                      (Unit, Document, State, Item.Channel_Name, Item.Value)
                  & ");",
                  Depth);
            when CM.Stmt_Receive =>
               State.Needs_Gnat_Adc := True;
               if State.Task_Body_Depth > 0 then
                  Append_Task_Channel_Call_Warning_Suppression (Buffer, Depth);
               end if;
               Append_Line
                 (Buffer,
                  Render_Expr (Unit, Document, Item.Channel_Name, State)
                  & ".Receive ("
                  & Render_Expr (Unit, Document, Item.Target, State)
                  & ");",
                  Depth);
               if State.Task_Body_Depth > 0 then
                  Append_Task_Channel_Call_Warning_Restore (Buffer, Depth);
               end if;
            when CM.Stmt_Try_Send =>
               State.Needs_Gnat_Adc := True;
               Append_Line
                 (Buffer,
                  Render_Expr (Unit, Document, Item.Channel_Name, State)
                  & ".Try_Send ("
                  & Render_Channel_Send_Value
                      (Unit, Document, State, Item.Channel_Name, Item.Value)
                  & ", "
                  & Render_Expr (Unit, Document, Item.Success_Var, State)
                  & ");",
                  Depth);
            when CM.Stmt_Try_Receive =>
               State.Needs_Gnat_Adc := True;
               if State.Task_Body_Depth > 0 then
                  Append_Task_Channel_Call_Warning_Suppression (Buffer, Depth);
               end if;
               Append_Line
                 (Buffer,
                  Render_Expr (Unit, Document, Item.Channel_Name, State)
                  & ".Try_Receive ("
                  & Render_Expr (Unit, Document, Item.Target, State)
                  & ", "
                  & Render_Expr (Unit, Document, Item.Success_Var, State)
                  & ");",
                  Depth);
               if State.Task_Body_Depth > 0 then
                  Append_Task_Channel_Call_Warning_Restore (Buffer, Depth);
               end if;
            when CM.Stmt_Select =>
               State.Needs_Gnat_Adc := True;
               declare
                  Channel_Arm_Count : Natural := 0;
                  Delay_Arm_Count   : Natural := 0;
               begin
                  for Arm of Item.Arms loop
                     if Arm.Kind = CM.Select_Arm_Channel then
                        Channel_Arm_Count := Channel_Arm_Count + 1;
                     elsif Arm.Kind = CM.Select_Arm_Delay then
                        Delay_Arm_Count := Delay_Arm_Count + 1;
                     end if;
                  end loop;

                  if Channel_Arm_Count = 0 then
                     Raise_Unsupported
                       (State,
                        Item.Span,
                        "select without channel arms is not supported in Ada emission");
                  end if;

                  if Delay_Arm_Count > 0 then
                     if Delay_Arm_Count /= 1 then
                        Raise_Unsupported
                          (State,
                           Item.Span,
                           "select with delay supports exactly one delay arm in Ada emission");
                     end if;

                     Append_Line (Buffer, "declare", Depth);
                     Append_Line (Buffer, "Select_Done : Boolean := False;", Depth + 1);
                     for Arm of Item.Arms loop
                        if Arm.Kind = CM.Select_Arm_Delay then
                           Append_Line
                             (Buffer,
                              "Select_Polls : constant Positive :="
                              & ASCII.LF
                              & Indentation (Depth + 2)
                              & "(if "
                              & Render_Expr (Unit, Document, Arm.Delay_Data.Duration_Expr, State)
                              & " <= 0.0"
                              & ASCII.LF
                              & Indentation (Depth + 3)
                              & "then 1"
                              & ASCII.LF
                              & Indentation (Depth + 3)
                              & "else Positive (Long_Float'Ceiling (1000.0 * Long_Float ("
                              & Render_Expr (Unit, Document, Arm.Delay_Data.Duration_Expr, State)
                              & "))));",
                              Depth + 1);
                           exit;
                        end if;
                     end loop;
                     Append_Line (Buffer, "begin", Depth);
                     Append_Line (Buffer, "for Select_Iter in 0 .. Select_Polls loop", Depth + 1);
                     Append_Line (Buffer, "exit when Select_Done;", Depth + 2);
                     Append_Line (Buffer, "if Select_Iter > 0 then", Depth + 2);
                     Append_Line (Buffer, "delay 0.001;", Depth + 3);
                     Append_Line (Buffer, "end if;", Depth + 2);

                     for Arm of Item.Arms loop
                        if Arm.Kind = CM.Select_Arm_Channel then
                           Append_Line (Buffer, "if not Select_Done then", Depth + 2);
                           Append_Line (Buffer, "declare", Depth + 3);
                           if State.Task_Body_Depth > 0 then
                              Append_Initialization_Warning_Suppression
                                (Buffer, Depth + 4);
                           end if;
                           Append_Line
                             (Buffer,
                              FT.To_String (Arm.Channel_Data.Variable_Name)
                              & " : "
                              & Render_Type_Name (Arm.Channel_Data.Type_Info)
                              & " := "
                              & Default_Value_Expr (Arm.Channel_Data.Type_Info)
                              & ";",
                              Depth + 4);
                           Append_Line (Buffer, "Arm_Success : Boolean := False;", Depth + 4);
                           if State.Task_Body_Depth > 0 then
                              Append_Initialization_Warning_Restore
                                (Buffer, Depth + 4);
                           end if;
                           Append_Line (Buffer, "begin", Depth + 3);
                           if State.Task_Body_Depth > 0 then
                              Append_Task_Channel_Call_Warning_Suppression
                                (Buffer, Depth + 4);
                           end if;
                           Append_Line
                             (Buffer,
                              Render_Expr (Unit, Document, Arm.Channel_Data.Channel_Name, State)
                              & ".Try_Receive ("
                              & FT.To_String (Arm.Channel_Data.Variable_Name)
                              & ", Arm_Success);",
                              Depth + 4);
                           if State.Task_Body_Depth > 0 then
                              Append_Task_Channel_Call_Warning_Restore
                                (Buffer, Depth + 4);
                              Append_Task_If_Warning_Suppression (Buffer, Depth + 4);
                           end if;
                           Append_Line (Buffer, "if Arm_Success then", Depth + 4);
                           Append_Line (Buffer, "Select_Done := True;", Depth + 5);
                           Render_Required_Statement_Suite
                             (Buffer,
                              Unit,
                              Document,
                              Arm.Channel_Data.Statements,
                              State,
                              Depth + 5,
                              Return_Type);
                           Append_Line (Buffer, "end if;", Depth + 4);
                           if State.Task_Body_Depth > 0 then
                              Append_Task_If_Warning_Restore (Buffer, Depth + 4);
                           end if;
                           Append_Line (Buffer, "end;", Depth + 3);
                           Append_Line (Buffer, "end if;", Depth + 2);
                        elsif Arm.Kind /= CM.Select_Arm_Delay then
                           Raise_Unsupported
                             (State,
                              Arm.Span,
                              "unsupported select arm in Ada emission");
                        end if;
                     end loop;

                     Append_Line (Buffer, "end loop;", Depth + 1);
                     for Arm of Item.Arms loop
                        if Arm.Kind = CM.Select_Arm_Delay then
                           if State.Task_Body_Depth > 0 then
                              Append_Task_If_Warning_Suppression (Buffer, Depth + 1);
                           end if;
                           Append_Line (Buffer, "if not Select_Done then", Depth + 1);
                           Render_Required_Statement_Suite
                             (Buffer,
                              Unit,
                              Document,
                              Arm.Delay_Data.Statements,
                              State,
                              Depth + 2,
                              Return_Type);
                           Append_Line (Buffer, "end if;", Depth + 1);
                           if State.Task_Body_Depth > 0 then
                              Append_Task_If_Warning_Restore (Buffer, Depth + 1);
                           end if;
                           exit;
                        end if;
                     end loop;
                     Append_Line (Buffer, "end;", Depth);
                  else
                     Append_Line (Buffer, "declare", Depth);
                     Append_Line (Buffer, "Select_Done : Boolean := False;", Depth + 1);
                     Append_Line (Buffer, "begin", Depth);
                     Append_Line (Buffer, "loop", Depth + 1);

                     for Arm of Item.Arms loop
                        if Arm.Kind = CM.Select_Arm_Channel then
                           Append_Line (Buffer, "if not Select_Done then", Depth + 2);
                           Append_Line (Buffer, "declare", Depth + 3);
                           if State.Task_Body_Depth > 0 then
                              Append_Initialization_Warning_Suppression
                                (Buffer, Depth + 4);
                           end if;
                           Append_Line
                             (Buffer,
                              FT.To_String (Arm.Channel_Data.Variable_Name)
                              & " : "
                              & Render_Type_Name (Arm.Channel_Data.Type_Info)
                              & " := "
                              & Default_Value_Expr (Arm.Channel_Data.Type_Info)
                              & ";",
                              Depth + 4);
                           Append_Line (Buffer, "Arm_Success : Boolean := False;", Depth + 4);
                           if State.Task_Body_Depth > 0 then
                              Append_Initialization_Warning_Restore
                                (Buffer, Depth + 4);
                           end if;
                           Append_Line (Buffer, "begin", Depth + 3);
                           if State.Task_Body_Depth > 0 then
                              Append_Task_Channel_Call_Warning_Suppression
                                (Buffer, Depth + 4);
                           end if;
                           Append_Line
                             (Buffer,
                              Render_Expr (Unit, Document, Arm.Channel_Data.Channel_Name, State)
                              & ".Try_Receive ("
                              & FT.To_String (Arm.Channel_Data.Variable_Name)
                              & ", Arm_Success);",
                              Depth + 4);
                           if State.Task_Body_Depth > 0 then
                              Append_Task_Channel_Call_Warning_Restore
                                (Buffer, Depth + 4);
                              Append_Task_If_Warning_Suppression (Buffer, Depth + 4);
                           end if;
                           Append_Line (Buffer, "if Arm_Success then", Depth + 4);
                           Append_Line (Buffer, "Select_Done := True;", Depth + 5);
                           Render_Required_Statement_Suite
                             (Buffer,
                              Unit,
                              Document,
                              Arm.Channel_Data.Statements,
                              State,
                              Depth + 5,
                              Return_Type);
                           Append_Line (Buffer, "end if;", Depth + 4);
                           if State.Task_Body_Depth > 0 then
                              Append_Task_If_Warning_Restore (Buffer, Depth + 4);
                           end if;
                           Append_Line (Buffer, "end;", Depth + 3);
                           Append_Line (Buffer, "end if;", Depth + 2);
                        elsif Arm.Kind /= CM.Select_Arm_Delay then
                           Raise_Unsupported
                             (State,
                              Arm.Span,
                              "unsupported select arm in Ada emission");
                        end if;
                     end loop;

                     Append_Line (Buffer, "exit when Select_Done;", Depth + 2);
                     Append_Line (Buffer, "delay 0.001;", Depth + 2);
                     Append_Line (Buffer, "end loop;", Depth + 1);
                     Append_Line (Buffer, "end;", Depth);
                  end if;
               end;
            when CM.Stmt_Delay =>
               State.Needs_Gnat_Adc := True;
               Append_Line
                 (Buffer,
                  "delay " & Render_Expr (Unit, Document, Item.Value, State) & ";",
                  Depth);
               when others =>
                  Raise_Unsupported
                    (State,
                     Item.Span,
                     "PR09 emitter does not yet support statement kind '"
                     & Item.Kind'Image
                     & "'");
            end case;
         end;
      end loop;
   end Render_Statements;

   procedure Render_Required_Statement_Suite
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False) is
   begin
      if Statements.Is_Empty then
         Append_Line (Buffer, "null;", Depth);
         return;
      end if;
      Render_Statements (Buffer, Unit, Document, Statements, State, Depth, Return_Type, In_Loop);
   end Render_Required_Statement_Suite;

   procedure Render_Channel_Spec
     (Buffer  : in out SU.Unbounded_String;
      Channel : CM.Resolved_Channel_Decl;
      Bronze  : MB.Bronze_Result)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Capacity      : constant String := Trim_Image (Channel.Capacity);
      Type_Name     : constant String := Name & "_Channel";
      Index_Subtype : constant String := Name & "_Index";
      Count_Subtype : constant String := Name & "_Count";
      Buffer_Type   : constant String := Name & "_Buffer";
      Send_Mode     : constant String :=
        (if Is_Owner_Access (Channel.Element_Type) then "in out " else "in ");
      Ceiling       : Long_Long_Integer :=
        (if Channel.Has_Required_Ceiling then Channel.Required_Ceiling else 0);
   begin
      for Item of Bronze.Ceilings loop
         if FT.To_String (Item.Channel_Name) = Name then
            Ceiling := Item.Priority;
            exit;
         end if;
      end loop;
      Append_Line
        (Buffer,
         "subtype " & Index_Subtype & " is Positive range 1 .. " & Capacity & ";",
         1);
      Append_Line
        (Buffer,
         "subtype " & Count_Subtype & " is Natural range 0 .. " & Capacity & ";",
         1);
      Append_Line
        (Buffer,
         "type " & Buffer_Type & " is array (" & Index_Subtype & ") of " & Element_Type & ";",
         1);
      Append_Line
        (Buffer,
         "protected type "
         & Type_Name
         & " with Priority => " & Trim_Image (Ceiling)
         & " is",
         1);
      Append_Line (Buffer, "entry Send (Value : " & Send_Mode & Element_Type & ");", 2);
      Append_Line (Buffer, "entry Receive (Value : out " & Element_Type & ");", 2);
      Append_Line
        (Buffer,
         "procedure Try_Send (Value : " & Send_Mode & Element_Type & "; Success : out Boolean);",
         2);
      Append_Line
        (Buffer,
         "procedure Try_Receive (Value : in out "
         & Element_Type
         & "; Success : out Boolean)"
         & (if Is_Owner_Access (Channel.Element_Type) then " with Pre => Value = null" else "")
         & ";",
         2);
      Append_Line (Buffer, "private", 1);
      Append_Line
         (Buffer,
          "Buffer : "
          & Buffer_Type
          & " := (others => "
          & Default_Value_Expr (Channel.Element_Type)
          & ");",
          2);
      Append_Line (Buffer, "Head   : " & Index_Subtype & " := " & Index_Subtype & "'First;", 2);
      Append_Line (Buffer, "Tail   : " & Index_Subtype & " := " & Index_Subtype & "'First;", 2);
      Append_Line (Buffer, "Count  : " & Count_Subtype & " := 0;", 2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer, Name & " : " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Channel_Spec;

   procedure Render_Channel_Body
     (Buffer  : in out SU.Unbounded_String;
      Channel : CM.Resolved_Channel_Decl)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Capacity      : constant String := Trim_Image (Channel.Capacity);
      Type_Name     : constant String := Name & "_Channel";
      Index_Subtype : constant String := Name & "_Index";
      Move_Helper   : constant String := Name & "_Move_From_Buffer";
      Is_Owner      : constant Boolean := Is_Owner_Access (Channel.Element_Type);
   begin
      if Is_Owner then
         Append_Line
           (Buffer,
            "procedure "
            & Move_Helper
            & " (Source : in out "
            & Element_Type
            & "; Target : out "
            & Element_Type
            & ") with Global => null is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "Target := Source;", 2);
         Append_Line (Buffer, "Source := null;", 2);
         Append_Line (Buffer, "end " & Move_Helper & ";", 1);
         Append_Line (Buffer);
      end if;
      Append_Line (Buffer, "protected body " & Type_Name & " is", 1);
      Append_Line
        (Buffer,
         "entry Send (Value : "
         & (if Is_Owner then "in out " else "in ")
         & Render_Type_Name (Channel.Element_Type)
         & ")",
         2);
      Append_Line
        (Buffer,
         "when Count < "
         & Capacity
         & " is",
         3);
      Append_Line (Buffer, "begin", 2);
      if Is_Owner then
         Append_Line (Buffer, Move_Helper & " (Value, Buffer (Tail));", 3);
      else
         Append_Line (Buffer, "Buffer (Tail) := Value;", 3);
      end if;
      Append_Line (Buffer, "if Tail = " & Index_Subtype & "'Last then", 3);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'First;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'Succ (Tail);", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "Count := Count + 1;", 3);
      Append_Line (Buffer, "end Send;", 2);
      Append_Line (Buffer);
      Append_Line (Buffer, "entry Receive (Value : out " & Render_Type_Name (Channel.Element_Type) & ")", 2);
      Append_Line
        (Buffer,
         "when Count > 0"
         & " is",
         3);
      Append_Line (Buffer, "begin", 2);
      if Is_Owner then
         Append_Line (Buffer, Move_Helper & " (Buffer (Head), Value);", 3);
      else
         Append_Line (Buffer, "Value := Buffer (Head);", 3);
         Append_Line
           (Buffer,
            "Buffer (Head) := " & Default_Value_Expr (Channel.Element_Type) & ";",
            3);
      end if;
      Append_Line (Buffer, "if Head = " & Index_Subtype & "'Last then", 3);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'First;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'Succ (Head);", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "Count := Count - 1;", 3);
      Append_Line (Buffer, "end Receive;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure Try_Send (Value : "
         & (if Is_Owner then "in out " else "in ")
         & Element_Type
         & "; Success : out Boolean) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line
        (Buffer,
         "if Count < "
         & Capacity
         & " then",
         3);
      if Is_Owner then
         Append_Line (Buffer, Move_Helper & " (Value, Buffer (Tail));", 4);
      else
         Append_Line (Buffer, "Buffer (Tail) := Value;", 4);
      end if;
      Append_Line (Buffer, "if Tail = " & Index_Subtype & "'Last then", 4);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'First;", 5);
      Append_Line (Buffer, "else", 4);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'Succ (Tail);", 5);
      Append_Line (Buffer, "end if;", 4);
      Append_Line (Buffer, "Count := Count + 1;", 4);
      Append_Line (Buffer, "Success := True;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Success := False;", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "end Try_Send;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure Try_Receive (Value : in out " & Element_Type & "; Success : out Boolean) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line
        (Buffer,
         "if Count > 0"
         & (if Is_Owner
              then
                " and then Value = "
                & Default_Value_Expr (Channel.Element_Type)
              else "")
         & " then",
         3);
      if Is_Owner then
         Append_Line (Buffer, Move_Helper & " (Buffer (Head), Value);", 4);
      else
         Append_Line (Buffer, "Value := Buffer (Head);", 4);
         Append_Line
           (Buffer,
            "Buffer (Head) := " & Default_Value_Expr (Channel.Element_Type) & ";",
            4);
      end if;
      Append_Line (Buffer, "if Head = " & Index_Subtype & "'Last then", 4);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'First;", 5);
      Append_Line (Buffer, "else", 4);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'Succ (Head);", 5);
      Append_Line (Buffer, "end if;", 4);
      Append_Line (Buffer, "Count := Count - 1;", 4);
      Append_Line (Buffer, "Success := True;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Success := False;", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "end Try_Receive;", 2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Channel_Body;

   procedure Render_Free_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
     Depth        : Natural)
   is
   begin
      pragma Unreferenced (Buffer, Declarations, Depth);
   end Render_Free_Declarations;

   procedure Render_Free_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural)
   is
   begin
      pragma Unreferenced (Buffer, Declarations, Depth);
   end Render_Free_Declarations;

   procedure Render_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State)
   is
      Raw_Outer_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Non_Alias_Declarations (Subprogram.Declarations);
      Inner_Alias_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Alias_Declarations (Subprogram.Declarations);
      Structural_Traversal_Lowering : constant Boolean :=
        Uses_Structural_Traversal_Lowering (Subprogram);
      Uses_Print : constant Boolean := Statements_Use_Print (Subprogram.Statements);
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;

      function Later_Outer_Declarations_Use_Name
        (Decl_Index : Positive;
         Name       : String) return Boolean is
      begin
         if Raw_Outer_Declarations.Is_Empty
           or else Decl_Index >= Raw_Outer_Declarations.Last_Index
         then
            return False;
         end if;

         for Later_Index in Decl_Index + 1 .. Raw_Outer_Declarations.Last_Index loop
            declare
               Later_Decl : constant CM.Resolved_Object_Decl :=
                 Raw_Outer_Declarations (Later_Index);
            begin
               if Later_Decl.Initializer /= null
                 and then Expr_Uses_Name (Later_Decl.Initializer, Name)
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Later_Outer_Declarations_Use_Name;

      function Should_Elide_Dead_Owner_Decl
        (Decl_Index : Positive;
         Decl       : CM.Resolved_Object_Decl) return Boolean is
         Decl_Name : constant String :=
           FT.To_String (Decl.Names (Decl.Names.First_Index));
      begin
         return
           not Decl.Is_Constant
           and then Is_Owner_Access (Decl.Type_Info)
           and then Decl.Has_Initializer
           and then Decl.Names.Length = 1
           and then Decl.Initializer /= null
           and then Decl.Initializer.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
           and then not
             Statements_Use_Name (Subprogram.Statements, Decl_Name)
           and then not Later_Outer_Declarations_Use_Name (Decl_Index, Decl_Name);
      end Should_Elide_Dead_Owner_Decl;

      function Effective_Outer_Declarations
        return CM.Resolved_Object_Decl_Vectors.Vector
      is
         Result : CM.Resolved_Object_Decl_Vectors.Vector;
      begin
         for Decl_Index in Raw_Outer_Declarations.First_Index .. Raw_Outer_Declarations.Last_Index loop
            declare
               Decl : constant CM.Resolved_Object_Decl :=
                 Raw_Outer_Declarations (Decl_Index);
            begin
               if not Should_Elide_Dead_Owner_Decl (Decl_Index, Decl) then
                  Result.Append (Decl);
               end if;
            end;
         end loop;
         return Result;
      end Effective_Outer_Declarations;

      Outer_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Effective_Outer_Declarations;
      Return_Type_Image : constant String :=
        (if Subprogram.Has_Return_Type then Render_Type_Name (Subprogram.Return_Type) else "");
      Suppress_Declaration_Warnings : constant Boolean :=
        not Structural_Traversal_Lowering and then not Outer_Declarations.Is_Empty;

      function Apply_Replacements
        (Text       : String;
         From_Names : FT.UString_Vectors.Vector;
         To_Names   : FT.UString_Vectors.Vector) return String
      is
         Result : SU.Unbounded_String := SU.To_Unbounded_String (Text);
      begin
         if From_Names.Length /= To_Names.Length then
            Raise_Internal
              ("structural traversal replacement table length mismatch during Ada emission");
         end if;

         if From_Names.Is_Empty then
            return Text;
         end if;

         for Index in From_Names.First_Index .. From_Names.Last_Index loop
            Result :=
              SU.To_Unbounded_String
                (Replace_Identifier_Token
                   (SU.To_String (Result),
                    FT.To_String (From_Names (Index)),
                    FT.To_String (To_Names (Index))));
         end loop;
         return SU.To_String (Result);
      end Apply_Replacements;

      function Render_Structural_Traversal_Body return Boolean is
         Subprogram_Name : constant String :=
           FT.Lowercase (FT.To_String (Subprogram.Name));

         function Is_Direct_Null_Check
           (Expr : CM.Expr_Access;
            Name : String) return Boolean;

         function Single_Return_Expr
           (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access;

         function Recursive_Call_From_Return
           (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access;

         function Is_Direct_Null_Check
           (Expr : CM.Expr_Access;
            Name : String) return Boolean
         is
            Operator : constant String :=
              (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
         begin
            return
              Expr /= null
              and then Expr.Kind = CM.Expr_Binary
              and then Operator = "="
              and then
                ((Expr.Left /= null
                  and then Expr.Left.Kind = CM.Expr_Ident
                  and then FT.To_String (Expr.Left.Name) = Name
                  and then Expr.Right /= null
                  and then Expr.Right.Kind = CM.Expr_Null)
                 or else
                 (Expr.Right /= null
                  and then Expr.Right.Kind = CM.Expr_Ident
                  and then FT.To_String (Expr.Right.Name) = Name
                  and then Expr.Left /= null
                  and then Expr.Left.Kind = CM.Expr_Null));
         end Is_Direct_Null_Check;

         function Single_Return_Expr
           (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access
         is
         begin
            if Statements.Length /= 1
              or else Statements (Statements.First_Index) = null
              or else Statements (Statements.First_Index).Kind /= CM.Stmt_Return
            then
               return null;
            end if;

            return Statements (Statements.First_Index).Value;
         end Single_Return_Expr;

         function Recursive_Call_From_Return
           (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access
         is
            Return_Expr : constant CM.Expr_Access := Single_Return_Expr (Statements);
         begin
            if Return_Expr /= null
              and then Return_Expr.Kind = CM.Expr_Call
              and then Return_Expr.Callee /= null
              and then FT.Lowercase (CM.Flatten_Name (Return_Expr.Callee)) = Subprogram_Name
            then
               return Return_Expr;
            end if;
            return null;
         end Recursive_Call_From_Return;

         function Render_Structural_Observer return Boolean is
            Param              : constant CM.Symbol :=
              Subprogram.Params (Subprogram.Params.First_Index);
            Param_Name         : constant String := FT.To_String (Param.Name);
            Param_Image        : constant String := Ada_Safe_Name (Param_Name);
            Cursor_Name        : constant String := "Cursor";
            Cursor_Type_Image  : constant String :=
              (if Has_Text (Param.Type_Info.Target)
               then "access constant " & FT.To_String (Param.Type_Info.Target)
               else "");
            If_Stmt            : CM.Statement_Access := null;
            Recursive_Call     : CM.Expr_Access := null;
            Default_Return_Expr : CM.Expr_Access := null;
            From_Names         : FT.UString_Vectors.Vector;
            To_Names           : FT.UString_Vectors.Vector;
         begin
            if not Subprogram.Declarations.Is_Empty
              or else Subprogram.Params.Length /= 1
              or else Subprogram.Statements.Length /= 1
              or else not Is_Owner_Access (Param.Type_Info)
              or else Cursor_Type_Image'Length = 0
            then
               return False;
            end if;

            If_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
            if If_Stmt = null
              or else If_Stmt.Kind /= CM.Stmt_If
              or else not Is_Direct_Null_Check (If_Stmt.Condition, Param_Name)
              or else not If_Stmt.Has_Else
            then
               return False;
            end if;

            Default_Return_Expr := Single_Return_Expr (If_Stmt.Then_Stmts);
            Recursive_Call := Recursive_Call_From_Return (If_Stmt.Else_Stmts);
            if Default_Return_Expr = null
              or else Recursive_Call = null
              or else Recursive_Call.Args.Length /= 1
              or else Root_Name (Recursive_Call.Args (Recursive_Call.Args.First_Index)) /= Param_Name
            then
               return False;
            end if;

            for Part of If_Stmt.Elsifs loop
               if Single_Return_Expr (Part.Statements) = null then
                  return False;
               end if;
            end loop;

            From_Names.Append (FT.To_UString (Param_Image));
            To_Names.Append (FT.To_UString (Cursor_Name));

            Append_Line
              (Buffer,
               Cursor_Name & " : " & Cursor_Type_Image & " := " & Param_Image & ";",
               2);
            Append_Line (Buffer, "begin", 1);
            Append_Line (Buffer, "while " & Cursor_Name & " /= null loop", 2);
            Append_Line (Buffer, "pragma Loop_Variant (Structural => " & Cursor_Name & ");", 3);

            for Part of If_Stmt.Elsifs loop
               declare
                  Branch_Return : constant CM.Expr_Access := Single_Return_Expr (Part.Statements);
               begin
                  Append_Line
                    (Buffer,
                     "if "
                     & Apply_Replacements
                         (Render_Expr (Unit, Document, Part.Condition, State),
                          From_Names,
                          To_Names)
                     & " then",
                     3);
                  Append_Line
                    (Buffer,
                     "return "
                     & Apply_Replacements
                         (Render_Expr (Unit, Document, Branch_Return, State),
                          From_Names,
                          To_Names)
                     & ";",
                     4);
                  Append_Line (Buffer, "end if;", 3);
               end;
            end loop;

            Append_Line
              (Buffer,
               Cursor_Name
               & " := "
               & Apply_Replacements
                   (Render_Expr
                      (Unit,
                       Document,
                       Recursive_Call.Args (Recursive_Call.Args.First_Index),
                       State),
                    From_Names,
                    To_Names)
               & ";",
               3);
            Append_Line (Buffer, "end loop;", 2);
            Append_Line
              (Buffer,
               "return "
               & Apply_Replacements
                   (Render_Expr (Unit, Document, Default_Return_Expr, State),
                    From_Names,
                    To_Names)
               & ";",
               2);
            return True;
         end Render_Structural_Observer;

         function Render_Structural_Accumulator return Boolean is
            First_Param       : constant CM.Symbol :=
              Subprogram.Params (Subprogram.Params.First_Index);
            First_Param_Name  : constant String := FT.To_String (First_Param.Name);
            First_Param_Image : constant String := Ada_Safe_Name (First_Param_Name);
            Cursor_Name       : constant String := "Cursor";
            Cursor_Type_Image : constant String :=
              (if Has_Text (First_Param.Type_Info.Target)
               then "access constant " & FT.To_String (First_Param.Type_Info.Target)
               else "");
            First_Stmt        : CM.Statement_Access := null;
            Recursive_Assign  : CM.Statement_Access := null;
            Final_Return      : CM.Statement_Access := null;
            Recursive_Call    : CM.Expr_Access := null;
            Entry_Exit_Image  : SU.Unbounded_String := SU.Null_Unbounded_String;
            Final_Return_Image : SU.Unbounded_String := SU.Null_Unbounded_String;
            Bound_Image       : SU.Unbounded_String := SU.Null_Unbounded_String;
            From_Names        : FT.UString_Vectors.Vector;
            To_Names          : FT.UString_Vectors.Vector;
            State_Names       : FT.UString_Vectors.Vector;
         begin
            if Subprogram.Declarations.Is_Empty
              or else Subprogram.Params.Length < 2
              or else Subprogram.Statements.Length < 4
              or else not Is_Owner_Access (First_Param.Type_Info)
              or else Cursor_Type_Image'Length = 0
            then
               return False;
            end if;

            First_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
            Recursive_Assign := Subprogram.Statements (Subprogram.Statements.Last_Index - 1);
            Final_Return := Subprogram.Statements (Subprogram.Statements.Last_Index);
            if First_Stmt = null
              or else First_Stmt.Kind /= CM.Stmt_If
              or else Single_Return_Expr (First_Stmt.Then_Stmts) = null
              or else First_Stmt.Has_Else
              or else not First_Stmt.Elsifs.Is_Empty
              or else Recursive_Assign = null
              or else Recursive_Assign.Kind /= CM.Stmt_Assign
              or else Recursive_Assign.Value = null
              or else Recursive_Assign.Value.Kind /= CM.Expr_Call
              or else Recursive_Assign.Value.Callee = null
              or else FT.Lowercase (CM.Flatten_Name (Recursive_Assign.Value.Callee)) /= Subprogram_Name
              or else Final_Return = null
              or else Final_Return.Kind /= CM.Stmt_Return
              or else Root_Name (Final_Return.Value) /= Root_Name (Recursive_Assign.Target)
            then
               return False;
            end if;

            Recursive_Call := Recursive_Assign.Value;
            if Recursive_Call.Args.Length /= Subprogram.Params.Length
              or else Root_Name (Recursive_Call.Args (Recursive_Call.Args.First_Index)) /= First_Param_Name
            then
               return False;
            end if;

            From_Names.Append (FT.To_UString (First_Param_Image));
            To_Names.Append (FT.To_UString (Cursor_Name));

            for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
               declare
                  Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
                  Param_Name : constant String := Ada_Safe_Name (FT.To_String (Param.Name));
                  State_Name : constant String := Param_Name & "_State";
               begin
                  State_Names.Append (FT.To_UString (State_Name));
                  From_Names.Append (FT.To_UString (Param_Name));
                  To_Names.Append (FT.To_UString (State_Name));
               end;
            end loop;

            for Arg_Index in Recursive_Call.Args.First_Index + 1 .. Recursive_Call.Args.Last_Index loop
               declare
                  Root : constant String := Ada_Safe_Name (Root_Name (Recursive_Call.Args (Arg_Index)));
               begin
                  if Root'Length > 0 then
                     From_Names.Append (FT.To_UString (Root));
                     To_Names.Append
                       (State_Names
                          (State_Names.First_Index
                           + (Arg_Index - (Recursive_Call.Args.First_Index + 1))));
                  end if;
               end;
            end loop;

            declare
               Leading_Condition : constant CM.Expr_Access := First_Stmt.Condition;
               Operator          : constant String :=
                 (if Leading_Condition = null then "" else Map_Operator (FT.To_String (Leading_Condition.Operator)));
               Leading_Return    : constant CM.Expr_Access :=
                 Single_Return_Expr (First_Stmt.Then_Stmts);
            begin
               if Is_Direct_Null_Check (Leading_Condition, First_Param_Name) then
                  null;
               elsif Leading_Condition /= null
                 and then Leading_Condition.Kind = CM.Expr_Binary
                 and then Operator = "or else"
               then
                  if Is_Direct_Null_Check (Leading_Condition.Left, First_Param_Name) then
                     Entry_Exit_Image :=
                       SU.To_Unbounded_String
                         (Apply_Replacements
                            (Render_Expr (Unit, Document, Leading_Condition.Right, State),
                             From_Names,
                             To_Names));
                  elsif Is_Direct_Null_Check (Leading_Condition.Right, First_Param_Name) then
                     Entry_Exit_Image :=
                       SU.To_Unbounded_String
                         (Apply_Replacements
                            (Render_Expr (Unit, Document, Leading_Condition.Left, State),
                             From_Names,
                             To_Names));
                  else
                     return False;
                  end if;
               else
                  return False;
               end if;

               Final_Return_Image :=
                 SU.To_Unbounded_String
                   (Apply_Replacements
                      (Render_Expr (Unit, Document, Leading_Return, State),
                       From_Names,
                       To_Names));
            end;

            Append_Line
              (Buffer,
               Cursor_Name & " : " & Cursor_Type_Image & " := " & First_Param_Image & ";",
               2);
            for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
               declare
                  Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
                  State_Name : constant String :=
                    FT.To_String
                      (State_Names
                         (State_Names.First_Index
                          + (Param_Index - (Subprogram.Params.First_Index + 1))));
               begin
                  Append_Line
                    (Buffer,
                     State_Name
                     & " : "
                     & Render_Type_Name (Param.Type_Info)
                     & " := "
                     & Ada_Safe_Name (FT.To_String (Param.Name))
                     & ";",
                     2);
               end;
            end loop;

            Append_Line (Buffer, "begin", 1);
            Append_Line (Buffer, "while " & Cursor_Name & " /= null loop", 2);
            Append_Line (Buffer, "pragma Loop_Variant (Structural => " & Cursor_Name & ");", 3);
            for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
               declare
                  Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
                  State_Name : constant String :=
                    FT.To_String
                      (State_Names
                         (State_Names.First_Index
                          + (Param_Index - (Subprogram.Params.First_Index + 1))));
               begin
                  if not Is_Access_Type (Param.Type_Info) then
                     Append_Line
                       (Buffer,
                        "pragma Loop_Invariant ("
                        & State_Name
                        & " in "
                        & Render_Type_Name (Param.Type_Info)
                        & ");",
                        3);
                  end if;
               end;
            end loop;
            if State_Names.Length >= 2 then
               Bound_Image :=
                 SU.To_Unbounded_String
                   (Structural_Accumulator_Count_Total_Bound
                      (Unit,
                       Document,
                       Subprogram,
                       FT.To_String (State_Names (State_Names.First_Index)),
                       FT.To_String (State_Names (State_Names.First_Index + 1)),
                       State));
               if SU.Length (Bound_Image) > 0 then
                  Append_Line
                    (Buffer,
                     "pragma Loop_Invariant (" & SU.To_String (Bound_Image) & ");",
                     3);
               end if;
            end if;

            if SU.Length (Entry_Exit_Image) > 0 then
               Append_Line (Buffer, "exit when " & SU.To_String (Entry_Exit_Image) & ";", 3);
            end if;

            for Statement_Index in Subprogram.Statements.First_Index + 1 .. Subprogram.Statements.Last_Index - 2 loop
               declare
                  Item : constant CM.Statement_Access := Subprogram.Statements (Statement_Index);
               begin
                  if Item = null then
                     return False;
                  end if;

                  case Item.Kind is
                     when CM.Stmt_Assign =>
                        declare
                           Target_Name : constant String :=
                             Apply_Replacements
                               (Ada_Safe_Name (Root_Name (Item.Target)),
                                From_Names,
                                To_Names);
                        begin
                           if Target_Name'Length = 0 then
                              return False;
                           end if;

                           Append_Line
                             (Buffer,
                              Target_Name
                              & " := "
                              & Apply_Replacements
                                  (Render_Expr (Unit, Document, Item.Value, State),
                                   From_Names,
                                   To_Names)
                              & ";",
                              3);
                        end;
                     when CM.Stmt_If =>
                        declare
                           Branch_Return : constant CM.Expr_Access :=
                             Single_Return_Expr (Item.Then_Stmts);
                           Branch_Return_Image : constant String :=
                             (if Branch_Return = null
                              then ""
                              else
                                Apply_Replacements
                                  (Render_Expr
                                     (Unit,
                                      Document,
                                      Branch_Return,
                                      State),
                                   From_Names,
                                   To_Names));
                        begin
                           if Branch_Return = null
                             or else Item.Has_Else
                             or else not Item.Elsifs.Is_Empty
                             or else Branch_Return_Image /= SU.To_String (Final_Return_Image)
                           then
                              return False;
                           end if;

                           Append_Line
                             (Buffer,
                              "exit when "
                              & Apply_Replacements
                                  (Render_Expr (Unit, Document, Item.Condition, State),
                                   From_Names,
                                   To_Names)
                              & ";",
                              3);
                        end;
                     when others =>
                        return False;
                  end case;
               end;
            end loop;

            Append_Line
              (Buffer,
               Cursor_Name
               & " := "
               & Apply_Replacements
                   (Render_Expr
                      (Unit,
                       Document,
                       Recursive_Call.Args (Recursive_Call.Args.First_Index),
                       State),
                    From_Names,
                    To_Names)
               & ";",
               3);
            Append_Line (Buffer, "end loop;", 2);
            Append_Line (Buffer, "return " & SU.To_String (Final_Return_Image) & ";", 2);
            return True;
         end Render_Structural_Accumulator;
      begin
         if Render_Structural_Observer then
            return True;
         end if;

         return Render_Structural_Accumulator;
      end Render_Structural_Traversal_Body;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Subprogram.Declarations, Subprogram.Statements);
      Push_Type_Binding_Frame (State);
      Register_Param_Type_Bindings (State, Subprogram.Params);
      Register_Type_Bindings (State, Outer_Declarations);
      Push_Cleanup_Frame (State);
      Register_Cleanup_Items (State, Outer_Declarations);
      Append_Line
        (Buffer,
         Render_Ada_Subprogram_Keyword (Subprogram)
         & " "
         & FT.To_String (Subprogram.Name)
         & Render_Subprogram_Params (Unit, Document, Subprogram.Params)
         & Render_Subprogram_Return (Unit, Document, Subprogram)
         & (if Uses_Print then " with SPARK_Mode => Off" else "")
         & " is",
         1);
      if Structural_Traversal_Lowering then
         if not Render_Structural_Traversal_Body then
            Raise_Internal
              ("structural traversal lowering matched a subprogram that could not be rendered");
         end if;
         Append_Line (Buffer, "end " & FT.To_String (Subprogram.Name) & ";", 1);
         Append_Line (Buffer);
         Pop_Cleanup_Frame (State);
         Pop_Type_Binding_Frame (State);
         Restore_Wide_Names (State, Previous_Wide_Count);
         return;
      end if;
      if Suppress_Declaration_Warnings then
         Append_Initialization_Warning_Suppression (Buffer, 2);
      end if;
      for Decl of Outer_Declarations loop
         Append_Line
           (Buffer,
            Render_Object_Decl_Text
              (Unit, Document, State, Decl, Local_Context => True),
            2);
         if Is_Owner_Access (Decl.Type_Info) then
            State.Needs_Unchecked_Deallocation := True;
         end if;
      end loop;
      Render_Free_Declarations (Buffer, Outer_Declarations, 2);
      if Suppress_Declaration_Warnings then
         Append_Initialization_Warning_Restore (Buffer, 2);
      end if;
      Append_Line (Buffer, "begin", 1);
      Render_In_Out_Param_Stabilizers (Buffer, Subprogram, 2);
      if not Inner_Alias_Declarations.Is_Empty then
         Push_Type_Binding_Frame (State);
         Register_Type_Bindings (State, Inner_Alias_Declarations);
         Append_Line (Buffer, "declare", 2);
         Render_Block_Declarations
           (Buffer, Unit, Document, Inner_Alias_Declarations, State, 3);
         Append_Line (Buffer, "begin", 2);
         Render_Required_Statement_Suite
           (Buffer,
            Unit,
            Document,
            Subprogram.Statements,
            State,
            3,
            Return_Type_Image);
         Append_Line (Buffer, "end;", 2);
         Pop_Type_Binding_Frame (State);
      else
         Render_Required_Statement_Suite
           (Buffer,
            Unit,
            Document,
            Subprogram.Statements,
            State,
            2,
            Return_Type_Image);
      end if;
      if Statements_Fall_Through (Subprogram.Statements) then
         Render_Cleanup (Buffer, Outer_Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Subprogram.Name) & ";", 1);
      Append_Line (Buffer);
      Pop_Cleanup_Frame (State);
      Pop_Type_Binding_Frame (State);
      Restore_Wide_Names (State, Previous_Wide_Count);
   end Render_Subprogram_Body;

   procedure Render_Task_Body
     (Buffer    : in out SU.Unbounded_String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Task_Item : CM.Resolved_Task;
      State     : in out Emit_State)
   is
      Uses_Print : constant Boolean := Statements_Use_Print (Task_Item.Statements);
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;
      Previous_Task_Body_Depth : constant Natural := State.Task_Body_Depth;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Task_Item.Declarations, Task_Item.Statements);
      Push_Type_Binding_Frame (State);
      Register_Type_Bindings (State, Task_Item.Declarations);
      Append_Line
        (Buffer,
         "task body "
         & FT.To_String (Task_Item.Name)
         & (if Uses_Print then " with SPARK_Mode => Off" else "")
         & " is",
         1);
      if not Task_Item.Declarations.Is_Empty then
         Append_Initialization_Warning_Suppression (Buffer, 2);
      end if;
      for Decl of Task_Item.Declarations loop
         Append_Line
           (Buffer,
            Render_Object_Decl_Text (Unit, Document, State, Decl, Local_Context => True),
            2);
         if Is_Owner_Access (Decl.Type_Info) then
            State.Needs_Unchecked_Deallocation := True;
         end if;
      end loop;
      Render_Free_Declarations (Buffer, Task_Item.Declarations, 2);
      if not Task_Item.Declarations.Is_Empty then
         Append_Initialization_Warning_Restore (Buffer, 2);
      end if;
      Append_Line (Buffer, "begin", 1);
      State.Task_Body_Depth := Previous_Task_Body_Depth + 1;
      Render_Required_Statement_Suite
        (Buffer, Unit, Document, Task_Item.Statements, State, 2, "");
      State.Task_Body_Depth := Previous_Task_Body_Depth;
      if Statements_Fall_Through (Task_Item.Statements) then
         Render_Cleanup (Buffer, Task_Item.Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Task_Item.Name) & ";", 1);
      Append_Line (Buffer);
      Pop_Type_Binding_Frame (State);
      State.Task_Body_Depth := Previous_Task_Body_Depth;
      Restore_Wide_Names (State, Previous_Wide_Count);
   end Render_Task_Body;

   function Unit_File_Stem (Unit_Name : String) return String is
      Result : String := Unit_Name;
   begin
      for Index in Result'Range loop
         if Result (Index) = '.' then
            Result (Index) := '-';
         else
            Result (Index) := Ada.Characters.Handling.To_Lower (Result (Index));
         end if;
      end loop;
      return Result;
   end Unit_File_Stem;

   function Safe_IO_Unit_Name (Unit_Name : String) return String is
      Base : String := Unit_Name;
   begin
      if Base'Length = 0 then
         return "generated_safe_io";
      end if;

      for Index in Base'Range loop
         if Base (Index) = '.' then
            Base (Index) := '_';
         else
            Base (Index) := Ada.Characters.Handling.To_Lower (Base (Index));
         end if;
      end loop;
      return Base & "_safe_io";
   end Safe_IO_Unit_Name;

   function Safe_IO_Spec_Text (Unit_Name : String) return String is
      Support_Name : constant String := Safe_IO_Unit_Name (Unit_Name);
   begin
      return
        Safe_IO_Support_Marker & ASCII.LF
        & ASCII.LF
        & "package "
        & Support_Name
        & ASCII.LF
        & "  with SPARK_Mode => Off" & ASCII.LF
        & "is" & ASCII.LF
        & "   procedure Put_Line (Text : String);" & ASCII.LF
        & "end "
        & Support_Name
        & ";" & ASCII.LF;
   end Safe_IO_Spec_Text;

   function Safe_IO_Body_Text (Unit_Name : String) return String is
      Support_Name : constant String := Safe_IO_Unit_Name (Unit_Name);
   begin
      return
        Safe_IO_Support_Marker & ASCII.LF
        & ASCII.LF
        & "with Ada.Text_IO;" & ASCII.LF
        & ASCII.LF
        & "package body "
        & Support_Name
        & ASCII.LF
        & "  with SPARK_Mode => Off" & ASCII.LF
        & "is" & ASCII.LF
        & "   procedure Put_Line (Text : String) is" & ASCII.LF
        & "   begin" & ASCII.LF
        & "      Ada.Text_IO.Put_Line (Text);" & ASCII.LF
        & "   end Put_Line;" & ASCII.LF
        & "end "
        & Support_Name
        & ";" & ASCII.LF;
   end Safe_IO_Body_Text;

   function Emit
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return Artifact_Result
   is
      State      : Emit_State;
      Unit_Uses_Print : constant Boolean := Statements_Use_Print (Unit.Statements);
      Spec_Inner : SU.Unbounded_String;
      Body_Inner : SU.Unbounded_String;
      Spec_Text  : SU.Unbounded_String;
      Body_Text  : SU.Unbounded_String;
      Body_Withs : FT.UString_Vectors.Vector;
      Synthetic_Types : GM.Type_Descriptor_Vectors.Vector;
      Owner_Access_Helper_Types : GM.Type_Descriptor_Vectors.Vector;

      procedure Add_Body_With (Name : String) is
      begin
         for Item of Body_Withs loop
            if FT.To_String (Item) = Name then
               return;
            end if;
         end loop;
         Body_Withs.Append (FT.To_UString (Name));
      end Add_Body_With;
   begin
      if not Unit.Channels.Is_Empty or else not Unit.Tasks.Is_Empty then
         State.Needs_Gnat_Adc := True;
      end if;
      Collect_Bounded_String_Types (Unit, Document, State);

      Append_Line (Spec_Inner, "pragma SPARK_Mode (On);");
      Append_Line (Spec_Inner);
      Append_Line
        (Spec_Inner,
         "package "
         & FT.To_String (Unit.Package_Name)
         & ASCII.LF
         & Indentation (1)
         & "with SPARK_Mode => On,"
         & ASCII.LF
         & Indentation (1)
         & "     Initializes => "
         & Render_Initializes_Aspect (Unit, Bronze)
         & ASCII.LF
         & "is");
      Append_Line (Spec_Inner, "pragma Elaborate_Body;", 1);
      Append_Line (Spec_Inner);
      Append_Bounded_String_Instantiations (Spec_Inner, State);

      for Type_Item of Unit.Types loop
         Append_Line (Spec_Inner, Render_Type_Decl (Type_Item, State), 1);
         if FT.To_String (Type_Item.Kind) = "record" then
            Append_Line (Spec_Inner);
         end if;
      end loop;

      Collect_Synthetic_Types (Unit, Document, Synthetic_Types);
      Collect_Owner_Access_Helper_Types (Unit, Document, Owner_Access_Helper_Types);
      for Type_Item of Synthetic_Types loop
         Append_Line (Spec_Inner, Render_Type_Decl (Type_Item, State), 1);
         Append_Line (Spec_Inner);
      end loop;

      for Type_Item of Owner_Access_Helper_Types loop
         Render_Owner_Access_Helper_Spec (Spec_Inner, Unit, Document, Type_Item);
      end loop;

      if not Unit.Objects.Is_Empty then
         for Decl of Unit.Objects loop
            Append_Line
              (Spec_Inner,
               Render_Object_Decl_Text (Unit, Document, State, Decl),
               1);
         end loop;
         Append_Line (Spec_Inner);
      end if;

      if not Unit.Channels.Is_Empty then
         for Channel of Unit.Channels loop
            Render_Channel_Spec (Spec_Inner, Channel, Bronze);
         end loop;
      end if;

      if not Unit.Subprograms.Is_Empty then
         for Subprogram of Unit.Subprograms loop
            Append_Line
              (Spec_Inner,
               Render_Ada_Subprogram_Keyword (Subprogram)
               & " "
               & FT.To_String (Subprogram.Name)
               & Render_Subprogram_Params (Unit, Document, Subprogram.Params)
               & Render_Subprogram_Return (Unit, Document, Subprogram)
               & Render_Subprogram_Aspects (Unit, Document, Subprogram, Bronze, State)
               & ";",
               1);
         end loop;
         Append_Line (Spec_Inner);
      end if;

      if not Unit.Tasks.Is_Empty then
         for Task_Item of Unit.Tasks loop
            Append_Line
              (Spec_Inner,
               "task "
               & FT.To_String (Task_Item.Name)
               & (if Task_Item.Has_Explicit_Priority
                  then " with Priority => " & Trim_Image (Task_Item.Priority)
                  else "")
               & ";",
               1);
         end loop;
         Append_Line (Spec_Inner);
      end if;

      Append_Line (Spec_Inner, "end " & FT.To_String (Unit.Package_Name) & ";");

      Append_Line
        (Body_Inner,
         "package body "
         & FT.To_String (Unit.Package_Name)
         & (if Unit_Uses_Print then " with SPARK_Mode => Off" else " with SPARK_Mode => On")
         & " is");
      Append_Bounded_String_Uses (Body_Inner, State, 1);
      Append_Line (Body_Inner);

      for Type_Item of Unit.Types loop
         Render_Growable_Array_Helper_Body
           (Body_Inner, Unit, Document, Type_Item, State);
      end loop;

      for Type_Item of Synthetic_Types loop
         Render_Growable_Array_Helper_Body
           (Body_Inner, Unit, Document, Type_Item, State);
      end loop;

      for Type_Item of Owner_Access_Helper_Types loop
         Render_Owner_Access_Helper_Body
           (Body_Inner, Unit, Document, Type_Item, State);
      end loop;

      for Channel of Unit.Channels loop
         Render_Channel_Body (Body_Inner, Channel);
      end loop;

      for Subprogram of Unit.Subprograms loop
         Render_Subprogram_Body (Body_Inner, Unit, Document, Subprogram, State);
      end loop;

      for Task_Item of Unit.Tasks loop
         Render_Task_Body (Body_Inner, Unit, Document, Task_Item, State);
      end loop;

      if not Unit.Statements.Is_Empty
        or else
          (for some Decl of Unit.Objects =>
             Decl.Has_Initializer
             and then not Decl.Is_Constant
             and then Has_Heap_Value_Type (Unit, Document, Decl.Type_Info))
      then
         Append_Line (Body_Inner, "begin");
         for Decl of Unit.Objects loop
            if Decl.Has_Initializer
              and then not Decl.Is_Constant
              and then Has_Heap_Value_Type (Unit, Document, Decl.Type_Info)
            then
               for Name of Decl.Names loop
                  Append_Line
                    (Body_Inner,
                     FT.To_String (Name)
                     & " := "
                     & Render_Expr_For_Target_Type
                         (Unit,
                          Document,
                          Decl.Initializer,
                          Decl.Type_Info,
                          State)
                     & ";",
                     1);
               end loop;
            end if;
         end loop;
         Render_Required_Statement_Suite
           (Body_Inner, Unit, Document, Unit.Statements, State, 1, "");
      end if;

      Append_Line (Body_Inner, "end " & FT.To_String (Unit.Package_Name) & ";");

      if State.Needs_Unchecked_Deallocation then
         Add_Body_With ("Ada.Unchecked_Deallocation");
      end if;
      if State.Needs_Ada_Strings_Unbounded then
         Add_Body_With ("Ada.Strings.Unbounded");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Body_Inner), "Ada.Strings.Fixed.") > 0 then
         Add_Body_With ("Ada.Strings");
         Add_Body_With ("Ada.Strings.Fixed");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Body_Inner), "Interfaces.") > 0 then
         Add_Body_With ("Interfaces");
      end if;
      if State.Needs_Safe_IO then
         Add_Body_With (Safe_IO_Unit_Name (FT.To_String (Unit.Package_Name)));
      end if;
      if State.Needs_Safe_Runtime then
         Add_Body_With ("Safe_Runtime");
      end if;
      if State.Needs_Safe_String_RT then
         Add_Body_With ("Safe_String_RT");
      end if;
      if State.Needs_Safe_Array_RT then
         Add_Body_With ("Safe_Array_RT");
      end if;

      for Item of Body_Withs loop
         Append_Line (Body_Text, "with " & FT.To_String (Item) & ";");
      end loop;
      if State.Needs_Safe_Runtime then
         Append_Line (Body_Text, "use type Safe_Runtime.Wide_Integer;");
      end if;
      if State.Needs_Safe_String_RT then
         Append_Line (Body_Text, "use type Safe_String_RT.Safe_String;");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Body_Inner), "Interfaces.") > 0 then
         Append_Line (Body_Text, "use type Interfaces.Unsigned_8;");
         Append_Line (Body_Text, "use type Interfaces.Unsigned_16;");
         Append_Line (Body_Text, "use type Interfaces.Unsigned_32;");
         Append_Line (Body_Text, "use type Interfaces.Unsigned_64;");
      end if;
      if not Body_Withs.Is_Empty then
         Append_Line (Body_Text);
      end if;
      Body_Text := Body_Text & Body_Inner;
      declare
         Original_Spec : constant String := SU.To_String (Spec_Inner);
         Pragma_Block  : constant String :=
           "pragma SPARK_Mode (On);" & ASCII.LF & ASCII.LF;
         Spec_Needs_Safe_Runtime : constant Boolean :=
           Ada.Strings.Fixed.Index (Original_Spec, "Safe_Runtime.") > 0;
         Spec_Needs_Safe_String_RT : constant Boolean :=
           Ada.Strings.Fixed.Index (Original_Spec, "Safe_String_RT.") > 0;
         Spec_Needs_Safe_Array_RT : constant Boolean :=
           Ada.Strings.Fixed.Index (Original_Spec, "Safe_Array_RT") > 0;
         Spec_Needs_Safe_Bounded_Strings : constant Boolean :=
           State.Needs_Safe_Bounded_Strings;
         Spec_Needs_Ada_Strings_Unbounded : constant Boolean :=
           State.Needs_Ada_Strings_Unbounded;
         Spec_Needs_Interfaces : constant Boolean :=
           Ada.Strings.Fixed.Index (Original_Spec, "Interfaces.") > 0;
      begin
         if (Spec_Needs_Safe_Runtime
             or else Spec_Needs_Safe_String_RT
             or else Spec_Needs_Safe_Array_RT
             or else Spec_Needs_Safe_Bounded_Strings
             or else Spec_Needs_Ada_Strings_Unbounded
             or else Spec_Needs_Interfaces
             or else State.Needs_Unevaluated_Use_Of_Old)
           and then Original_Spec'Length >= Pragma_Block'Length
           and then
             Original_Spec
               (Original_Spec'First .. Original_Spec'First + Pragma_Block'Length - 1) =
               Pragma_Block
         then
            Append_Line (Spec_Text, "pragma SPARK_Mode (On);");
            if State.Needs_Unevaluated_Use_Of_Old then
               Append_Line (Spec_Text, "pragma Unevaluated_Use_Of_Old (Allow);");
            end if;
            if Spec_Needs_Ada_Strings_Unbounded then
               Append_Line (Spec_Text, "with Ada.Strings.Unbounded;");
            end if;
            if Spec_Needs_Safe_String_RT then
               Append_Line (Spec_Text, "with Safe_String_RT;");
            end if;
            if Spec_Needs_Safe_Array_RT then
               Append_Line (Spec_Text, "with Safe_Array_RT;");
            end if;
            if Spec_Needs_Safe_Bounded_Strings then
               Append_Line (Spec_Text, "with Safe_Bounded_Strings;");
            end if;
            if Spec_Needs_Interfaces then
               Append_Line (Spec_Text, "with Interfaces;");
               Append_Line (Spec_Text, "use type Interfaces.Unsigned_8;");
               Append_Line (Spec_Text, "use type Interfaces.Unsigned_16;");
               Append_Line (Spec_Text, "use type Interfaces.Unsigned_32;");
               Append_Line (Spec_Text, "use type Interfaces.Unsigned_64;");
            end if;
            if Spec_Needs_Safe_Runtime then
               Append_Line (Spec_Text, "with Safe_Runtime;");
               Append_Line (Spec_Text, "use type Safe_Runtime.Wide_Integer;");
            end if;
            Append_Line (Spec_Text);
            Spec_Text :=
              Spec_Text
              & SU.To_Unbounded_String
                  (Original_Spec
                     (Original_Spec'First + Pragma_Block'Length .. Original_Spec'Last));
         else
            Spec_Text := Spec_Text & Spec_Inner;
         end if;
      end;

      return
        (Success            => True,
         Unit_Name          => Unit.Package_Name,
         Spec_Text          => FT.To_UString (SU.To_String (Spec_Text)),
         Body_Text          => FT.To_UString (SU.To_String (Body_Text)),
         Safe_IO_Unit_Name  =>
           (if State.Needs_Safe_IO
            then FT.To_UString (Safe_IO_Unit_Name (FT.To_String (Unit.Package_Name)))
            else FT.To_UString ("")),
         Needs_Safe_IO      => State.Needs_Safe_IO,
         Needs_Safe_Runtime => State.Needs_Safe_Runtime,
         Needs_Safe_String_RT => State.Needs_Safe_String_RT,
         Needs_Safe_Array_RT => State.Needs_Safe_Array_RT,
         Needs_Safe_Bounded_Strings => State.Needs_Safe_Bounded_Strings,
         Needs_Gnat_Adc     => State.Needs_Gnat_Adc);
   exception
      when Emitter_Unsupported =>
         return
           (Success    => False,
            Diagnostic =>
              CM.Unsupported_Source_Construct
                (Path    => FT.To_String (Unit.Path),
                 Span    => State.Unsupported_Span,
                 Message => FT.To_String (State.Unsupported_Message)));
   end Emit;
end Safe_Frontend.Ada_Emit;
