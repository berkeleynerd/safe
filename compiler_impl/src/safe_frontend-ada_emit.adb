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

   Gnat_Adc_Contents : constant String :=
     "pragma Partition_Elaboration_Policy(Sequential);" & ASCII.LF
     & "pragma Profile(Jorvik);" & ASCII.LF;

   type Cleanup_Action is (Cleanup_Deallocate, Cleanup_Reset_Null);

   type Cleanup_Item is record
      Action    : Cleanup_Action := Cleanup_Deallocate;
      Name      : FT.UString := FT.To_UString ("");
      Type_Name : FT.UString := FT.To_UString ("");
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

   type Emit_State is record
      Needs_Safe_Runtime : Boolean := False;
      Needs_Ada_Strings_Unbounded : Boolean := False;
      Needs_Unevaluated_Use_Of_Old : Boolean := False;
      Needs_Gnat_Adc     : Boolean := False;
      Needs_Unchecked_Deallocation : Boolean := False;
      Wide_Local_Names   : FT.UString_Vectors.Vector;
      Unsupported_Span   : FT.Source_Span := FT.Null_Span;
      Unsupported_Message : FT.UString := FT.To_UString ("");
      Cleanup_Stack      : Cleanup_Frame_Vectors.Vector;
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
   procedure Push_Cleanup_Frame (State : in out Emit_State);
   procedure Pop_Cleanup_Frame (State : in out Emit_State);
   procedure Add_Cleanup_Item
     (State     : in out Emit_State;
      Name      : String;
      Type_Name : String;
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
      Depth  : Natural);
   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean;
   function Starts_With (Text : String; Prefix : String) return Boolean;
   function Ada_Safe_Name (Name : String) return String;
   function Normalize_Aspect_Name
     (Subprogram_Name : String;
      Raw_Name        : String) return String;
   function Is_Attribute_Selector (Name : String) return Boolean;
   function Root_Name (Expr : CM.Expr_Access) return String;
   function Expr_Uses_Name
     (Expr : CM.Expr_Access;
      Name : String) return Boolean;
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
   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Float_Type
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
   function Is_String_Type_Name (Name : String) return Boolean;
   function Tuple_Field_Name (Index : Positive) return String;
   function Tuple_String_Discriminant_Name (Index : Positive) return String;
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
   function Default_Value_Expr (Info : GM.Type_Descriptor) return String;
   function Render_Type_Name (Info : GM.Type_Descriptor) return String;
   function Render_Param_Type_Name (Info : GM.Type_Descriptor) return String;
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
      Initializer    : CM.Expr_Access;
      Local_Context  : Boolean := False) return String;
   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl;
   function Render_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
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
   function Uses_Wide_Arithmetic
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean;
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
      Condition : CM.Expr_Access) return String;

   function Render_Subprogram_Params
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Params     : CM.Symbol_Vectors.Vector) return String;
   function Render_Ada_Subprogram_Keyword
     (Subprogram : CM.Resolved_Subprogram) return String;
   function Render_Subprogram_Return
     (Subprogram : CM.Resolved_Subprogram) return String;
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
                  Decl.Is_Constant);
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
                  Decl.Is_Constant);
            end loop;
         end if;
      end loop;
   end Register_Cleanup_Items;

   procedure Render_Cleanup_Item
     (Buffer : in out SU.Unbounded_String;
      Item   : Cleanup_Item;
      Depth  : Natural) is
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
                  "Free_" & FT.To_String (Item.Type_Name) & " (Cleanup_Target);",
                  Depth + 1);
               Append_Line (Buffer, "end;", Depth);
            else
               Append_Line
                 (Buffer,
                  "Free_" & FT.To_String (Item.Type_Name) & " (" & FT.To_String (Item.Name) & ");",
                  Depth);
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
      Depth  : Natural) is
   begin
      if State.Cleanup_Stack.Is_Empty then
         return;
      end if;
      for Frame_Index in reverse State.Cleanup_Stack.First_Index .. State.Cleanup_Stack.Last_Index loop
         declare
            Frame : constant Cleanup_Frame := State.Cleanup_Stack (Frame_Index);
         begin
            for Item_Index in reverse Frame.Items.First_Index .. Frame.Items.Last_Index loop
               Render_Cleanup_Item (Buffer, Frame.Items (Item_Index), Depth);
            end loop;
         end;
      end loop;
   end Render_Active_Cleanup;

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

   function Ada_Safe_Name (Name : String) return String is
   begin
      if Name = "integer" then
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

   function Is_String_Type_Name (Name : String) return Boolean is
   begin
      return FT.Lowercase (Name) = "string";
   end Is_String_Type_Name;

   function Tuple_Field_Name (Index : Positive) return String is
   begin
      return "F" & Ada.Strings.Fixed.Trim (Positive'Image (Index), Ada.Strings.Both);
   end Tuple_Field_Name;

   function Tuple_String_Discriminant_Name (Index : Positive) return String is
   begin
      return Tuple_Field_Name (Index) & "_Length";
   end Tuple_String_Discriminant_Name;

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
         if not First_Association then
            Result := Result & SU.To_Unbounded_String (", ");
         end if;
         Result :=
           Result
           & SU.To_Unbounded_String
               (FT.To_String (Field.Field_Name)
                & " => "
                & Render_Expr (Unit, Document, Field.Expr, State));
         First_Association := False;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Record_Aggregate_For_Type;

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
      elsif Expr.Kind = CM.Expr_String and then Has_Text (Expr.Text) then
         return "String'(" & FT.To_String (Expr.Text) & ")'Length";
      end if;

      return
        "String'("
        & Render_Expr (Unit, Document, Expr, State)
        & ")'Length";
   end Render_String_Length_Expr;

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
         return
           Ada_Safe_Name (FT.To_String (Info.Base))
           & " range "
           & Trim_Image (Info.Low)
           & " .. "
           & Trim_Image (Info.High);
      end if;
      return Ada_Safe_Name (FT.To_String (Info.Name));
   end Render_Type_Name;

   function Render_Param_Type_Name (Info : GM.Type_Descriptor) return String is
      Param_Info : GM.Type_Descriptor := Info;
   begin
      if Param_Info.Anonymous and then Is_Alias_Access (Param_Info) then
         Param_Info.Not_Null := True;
      end if;
      return Render_Type_Name (Param_Info);
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
      elsif Type_Name = "float" or else Type_Name = "long_float" then
         return "0.0";
      elsif Starts_With (Type_Name, "access ")
        or else Starts_With (Type_Name, "not null access ")
        or else Starts_With (Type_Name, "access constant ")
        or else Starts_With (Type_Name, "not null access constant ")
      then
         return "null";
      end if;
      return Type_Name & "'First";
   end Default_Value_Expr;

   function Default_Value_Expr (Info : GM.Type_Descriptor) return String is
      Type_Name : constant String := Render_Type_Name (Info);
      Kind      : constant String := FT.To_String (Info.Kind);
      Result    : SU.Unbounded_String;
   begin
      if Kind = "access" then
         return "null";
      elsif Is_Tuple_Type (Info) then
         declare
            First_Association : Boolean := True;
         begin
            Result := SU.To_Unbounded_String ("(");
            for Index in Info.Tuple_Element_Types.First_Index .. Info.Tuple_Element_Types.Last_Index loop
               if Is_String_Type_Name (FT.To_String (Info.Tuple_Element_Types (Index))) then
                  if not First_Association then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (Tuple_String_Discriminant_Name (Positive (Index)) & " => 0");
                  First_Association := False;
               end if;
            end loop;
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
      Seen : FT.UString_Vectors.Vector;

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
      begin
         if not Has_Text (Info.Name) then
            return;
         end if;

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

      procedure Add_From_Decls (Decls : CM.Object_Decl_Vectors.Vector) is
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
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
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

   function Render_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Kind : constant String := FT.To_String (Type_Item.Kind);
      Result : SU.Unbounded_String;
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
         return
           "type "
           & Ada_Safe_Name (Name)
           & " is array ("
           & Join_Names (Type_Item.Index_Types)
           & ") of "
           & Ada_Safe_Name (FT.To_String (Type_Item.Component_Type))
           & ";";
      elsif Kind = "tuple" then
         Result := SU.To_Unbounded_String ("type " & Ada_Safe_Name (Name));
         declare
            First_Discriminant : Boolean := True;
         begin
            for Index in Type_Item.Tuple_Element_Types.First_Index .. Type_Item.Tuple_Element_Types.Last_Index loop
               if Is_String_Type_Name (FT.To_String (Type_Item.Tuple_Element_Types (Index))) then
                  if First_Discriminant then
                     Result := Result & SU.To_Unbounded_String (" (");
                     First_Discriminant := False;
                  else
                     Result := Result & SU.To_Unbounded_String ("; ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (Tuple_String_Discriminant_Name (Positive (Index))
                         & " : Natural := 0");
               end if;
            end loop;
            if not First_Discriminant then
               Result := Result & SU.To_Unbounded_String (")");
            end if;
         end;
         Result := Result & SU.To_Unbounded_String (" is record" & ASCII.LF);
         for Index in Type_Item.Tuple_Element_Types.First_Index .. Type_Item.Tuple_Element_Types.Last_Index loop
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Indentation (1)
                   & Tuple_Field_Name (Positive (Index))
                   & " : "
                   & (if Is_String_Type_Name (FT.To_String (Type_Item.Tuple_Element_Types (Index)))
                      then
                        "String (1 .. "
                        & Tuple_String_Discriminant_Name (Positive (Index))
                        & ")"
                      else
                        Ada_Safe_Name (FT.To_String (Type_Item.Tuple_Element_Types (Index))))
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
                     Ada_Safe_Name (FT.To_String (Field.Type_Name)),
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
                              Ada_Safe_Name (FT.To_String (Type_Item.Variant_Fields (Index).Type_Name)),
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
         return
           "type "
           & Name
           & " is "
           & (if Type_Item.Not_Null then "not null " else "")
           & "access "
           & (if Type_Item.Is_Constant then "constant " else "")
           & FT.To_String (Type_Item.Target)
           & ";";
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

   function Map_Operator (Operator : String) return String is
   begin
      if Operator = "!=" then
         return "/=";
      elsif Operator = "==" then
         return "=";
      end if;
      return Operator;
   end Map_Operator;

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
         when CM.Expr_String | CM.Expr_Char =>
            if Has_Text (Expr.Text) then
               return FT.To_String (Expr.Text);
            end if;
            Raise_Unsupported
              (State,
               Expr.Span,
               "text literal missing source text");
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
            return FT.To_String (Expr.Name);
         when CM.Expr_Select =>
            declare
               Prefix_Image  : constant String := Render_Expr (Unit, Document, Expr.Prefix, State);
               Selector_Name : constant String := FT.To_String (Expr.Selector);
            begin
               if Selector_Name = "access"
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
               return Prefix_Image & "." & Selector_Name;
            end;
         when CM.Expr_Resolved_Index =>
            Result :=
              SU.To_Unbounded_String
                (Render_Expr (Unit, Document, Expr.Prefix, State) & " (");
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
                      (Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State));
               end if;
               if Expr.Args.Is_Empty then
                  return Callee_Image;
               end if;
               Result := SU.To_Unbounded_String (Callee_Image & " (");
            end;
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
               First_Association : Boolean := True;
            begin
               Result := SU.To_Unbounded_String ("(");
               for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
                  if Expr.Elements (Index) /= null
                    and then Is_String_Type_Name (FT.To_String (Expr.Elements (Index).Type_Name))
                  then
                     if not First_Association then
                        Result := Result & SU.To_Unbounded_String (", ");
                     end if;
                     Result :=
                       Result
                       & SU.To_Unbounded_String
                           (Tuple_String_Discriminant_Name (Positive (Index))
                            & " => "
                            & Render_String_Length_Expr
                                (Unit,
                                 Document,
                                 Expr.Elements (Index),
                                 State));
                     First_Association := False;
                  end if;
               end loop;
               for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
                  if not First_Association then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (Tuple_Field_Name (Positive (Index))
                         & " => "
                         & Render_Expr (Unit, Document, Expr.Elements (Index), State));
                  First_Association := False;
               end loop;
            end;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Annotated =>
            return
              Render_Expr (Unit, Document, Expr.Target, State)
              & "'"
              & (if Expr.Inner /= null and then Expr.Inner.Kind = CM.Expr_Aggregate
                 then Render_Expr (Unit, Document, Expr.Inner, State)
                 else "(" & Render_Expr (Unit, Document, Expr.Inner, State) & ")");
         when CM.Expr_Unary =>
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

   function Uses_Wide_Arithmetic
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean
   is
      Operator : constant String :=
        (if Expr = null then "" else FT.To_String (Expr.Operator));
   begin
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Unary =>
            return
              Operator = "-"
              and then Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name));
         when CM.Expr_Binary =>
            if Operator in "+" | "-" | "*" | "/" | "mod" | "rem" then
               return Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name));
            end if;
            return
              Uses_Wide_Arithmetic (Unit, Document, Expr.Left)
              or else Uses_Wide_Arithmetic (Unit, Document, Expr.Right);
         when CM.Expr_Conversion =>
            return Uses_Wide_Arithmetic (Unit, Document, Expr.Inner);
         when CM.Expr_Annotated =>
            return Uses_Wide_Arithmetic (Unit, Document, Expr.Inner);
         when CM.Expr_Call =>
            for Item of Expr.Args loop
               if Uses_Wide_Arithmetic (Unit, Document, Item) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Resolved_Index =>
            for Item of Expr.Args loop
               if Uses_Wide_Arithmetic (Unit, Document, Item) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Uses_Wide_Arithmetic;

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
      Initializer    : CM.Expr_Access;
      Local_Context  : Boolean := False) return String
   is
      Result : SU.Unbounded_String;
      Type_Name : constant String :=
        (if Is_Integer_Type (Unit, Document, Type_Info)
           and then Names_Use_Wide_Storage (State, Names)
         then "safe_runtime.wide_integer"
         elsif Local_Context
           and then Is_Access_Type (Type_Info)
           and then not Is_Owner_Access (Type_Info)
           and then Has_Text (Type_Info.Target)
         then
           "access "
           & (if Type_Info.Is_Constant then "constant " else "")
           & FT.To_String (Type_Info.Target)
         else Render_Type_Name (Type_Info));
      function Render_Initializer return String is
      begin
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
           and then Initializer.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
           and then Type_Name /= "safe_runtime.wide_integer"
         then
            return Type_Name & "'" & Render_Expr (Unit, Document, Initializer, State);
         end if;
         return Render_Expr (Unit, Document, Initializer, State);
      end Render_Initializer;
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
                & (if Is_Constant then "constant " else "")
                & Type_Name);
         if Has_Initializer then
            if Type_Name = "safe_runtime.wide_integer" then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Render_Wide_Expr (Unit, Document, Initializer, State));
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
           Initializer     => Decl.Initializer,
           Local_Context   => Local_Context);
   end Render_Object_Decl_Text;

   function Render_Subprogram_Params
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Params     : CM.Symbol_Vectors.Vector) return String
   is
      pragma Unreferenced (Unit, Document);
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
                   & (if Mode = "in" or else Mode = "" then "" else Mode & " ")
                   & Render_Param_Type_Name (Param.Type_Info));
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Subprogram_Params;

   function Render_Subprogram_Return
     (Subprogram : CM.Resolved_Subprogram) return String is
   begin
      if Subprogram.Has_Return_Type then
         return " return " & Render_Type_Name (Subprogram.Return_Type);
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
         if FT.To_String (Param.Mode) = "in out"
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
            if Mode = "out" then
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

      procedure Add_Unique (Condition : String) is
      begin
         if Condition'Length > 0 and then not Contains_Name (Conditions, Condition) then
            Conditions.Append (FT.To_UString (Condition));
         end if;
      end Add_Unique;

      procedure Collect
        (Statements : CM.Statement_Access_Vectors.Vector);

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
                     end;
                  when CM.Stmt_If =>
                     Collect (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Collect (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Collect (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     Collect (Item.Body_Stmts);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Collect (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
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
         when CM.Expr_String | CM.Expr_Char =>
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
         when CM.Expr_Int | CM.Expr_Real | CM.Expr_String | CM.Expr_Char
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
            return
               "("
               & Map_Operator (FT.To_String (Expr.Operator))
               & (if FT.To_String (Expr.Operator) = "not" then " " else "")
               & Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Inner, Target, Replacement, State, Supported)
               & ")";
         when CM.Expr_Binary =>
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
      Global_Image  : constant String := Render_Global_Aspect (Unit, Summary);
      Depends_Image : constant String :=
        Render_Depends_Aspect (Unit, Subprogram, Summary);
      Pre_Image : constant String :=
        Render_Access_Param_Precondition (Unit, Document, Subprogram, State);
      Post_Image : constant String :=
        Render_Access_Param_Postcondition (Unit, Document, Subprogram, State);
      Result : SU.Unbounded_String :=
        SU.To_Unbounded_String (" with Global => " & Global_Image);
   begin
      if not Has_Text (Summary.Name) then
         return "";
      end if;

      if Depends_Image'Length > 0 then
         Result :=
           Result
           & SU.To_Unbounded_String
               ("," & ASCII.LF
                & Indentation (4)
                & "Depends => ("
                & Depends_Image
                & ")");
      end if;
      if Pre_Image'Length > 0 then
         Result :=
           Result
           & SU.To_Unbounded_String
               ("," & ASCII.LF
                & Indentation (4)
                & "Pre => "
                & Pre_Image);
      end if;
      if Post_Image'Length > 0 then
         Result :=
           Result
           & SU.To_Unbounded_String
               ("," & ASCII.LF
                & Indentation (4)
                & "Post => "
                & Post_Image);
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
      Condition : CM.Expr_Access) return String
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
      end if;

      return "";
   end Loop_Variant_Image;

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
        (if Has_Type (Unit, Document, Target_Type)
         then Lookup_Type (Unit, Document, Target_Type)
         else (others => <>));
      Target_Image : constant String := Render_Expr (Unit, Document, Stmt.Target, State);
      Value_Image  : constant String := Render_Expr (Unit, Document, Stmt.Value, State);
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
        (if Return_Type'Length > 0 and then Has_Type (Unit, Document, Return_Type)
         then Lookup_Type (Unit, Document, Return_Type)
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
        (if Has_Type (Unit, Document, Value_Type)
         then Lookup_Type (Unit, Document, Value_Type)
         else (others => <>));
      Needs_Move_Null : constant Boolean :=
        Has_Type (Unit, Document, Value_Type)
        and then Is_Owner_Access (Value_Info)
        and then Value.Kind in CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index;
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
            & Render_Expr (Unit, Document, Value, State)
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
      if Needs_Move_Null then
         Append_Move_Null (Buffer, Unit, Document, State, Value, Depth + 1);
      end if;
      Render_Active_Cleanup (Buffer, State, Depth + 1);
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

   procedure Render_Block_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Declarations : CM.Object_Decl_Vectors.Vector;
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
                      Is_Constant => Decl.Is_Constant),
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
                      Is_Constant => Decl.Is_Constant),
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
                  Push_Cleanup_Frame (State);
                  Register_Cleanup_Items (State, Block_Declarations);
                  Append_Line (Buffer, "declare", Depth);
                  Append_Line
                    (Buffer,
                     Render_Object_Decl_Text (Unit, Document, State, Item.Decl, Local_Context => True),
                     Depth + 1);
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
                  Restore_Wide_Names (State, Previous_Wide_Count);
               end;
               return;
            when CM.Stmt_Assign =>
               Append_Assignment (Buffer, Unit, Document, State, Item.all, Depth);
               if In_Loop then
                  Append_Integer_Loop_Invariant
                    (Buffer, Unit, Document, State, Item.Target, Depth);
                  Append_Float_Loop_Invariant
                    (Buffer, Unit, Document, State, Item.Target, Depth);
               end if;
            when CM.Stmt_Call =>
               Append_Line
                 (Buffer,
                  Render_Expr (Unit, Document, Item.Call, State) & ";",
                  Depth);
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
            when CM.Stmt_Case =>
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
            when CM.Stmt_While =>
               Append_Line
                 (Buffer,
                  "while " & Render_Expr (Unit, Document, Item.Condition, State) & " loop",
                  Depth);
               declare
                  Variant_Image : constant String := Loop_Variant_Image (Unit, Document, Item.Condition);
               begin
                  if Variant_Image'Length > 0 then
                     Append_Line (Buffer, "pragma Loop_Variant (" & Variant_Image & ");", Depth + 1);
                  end if;
               end;
               Render_Required_Statement_Suite
                 (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
               Append_Line (Buffer, "end loop;", Depth);
            when CM.Stmt_For =>
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
               Append_Line
                 (Buffer,
                  Render_Expr (Unit, Document, Item.Channel_Name, State)
                  & ".Receive ("
                  & Render_Expr (Unit, Document, Item.Target, State)
                  & ");",
                  Depth);
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
               Append_Line
                 (Buffer,
                  Render_Expr (Unit, Document, Item.Channel_Name, State)
                  & ".Try_Receive ("
                  & Render_Expr (Unit, Document, Item.Target, State)
                  & ", "
                  & Render_Expr (Unit, Document, Item.Success_Var, State)
                  & ");",
                  Depth);
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
                           Append_Line
                             (Buffer,
                              FT.To_String (Arm.Channel_Data.Variable_Name)
                              & " : "
                              & Render_Type_Name (Arm.Channel_Data.Type_Info)
                              & " := "
                              & Default_Value_Expr (Arm.Channel_Data.Type_Info)
                              & ";",
                              Depth + 4);
                           Append_Line (Buffer, "Arm_Success : Boolean;", Depth + 4);
                           Append_Line (Buffer, "begin", Depth + 3);
                           Append_Line
                             (Buffer,
                              Render_Expr (Unit, Document, Arm.Channel_Data.Channel_Name, State)
                              & ".Try_Receive ("
                              & FT.To_String (Arm.Channel_Data.Variable_Name)
                              & ", Arm_Success);",
                              Depth + 4);
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
                           Append_Line
                             (Buffer,
                              FT.To_String (Arm.Channel_Data.Variable_Name)
                              & " : "
                              & Render_Type_Name (Arm.Channel_Data.Type_Info)
                              & " := "
                              & Default_Value_Expr (Arm.Channel_Data.Type_Info)
                              & ";",
                              Depth + 4);
                           Append_Line (Buffer, "Arm_Success : Boolean;", Depth + 4);
                           Append_Line (Buffer, "begin", Depth + 3);
                           Append_Line
                             (Buffer,
                              Render_Expr (Unit, Document, Arm.Channel_Data.Channel_Name, State)
                              & ".Try_Receive ("
                              & FT.To_String (Arm.Channel_Data.Variable_Name)
                              & ", Arm_Success);",
                              Depth + 4);
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
      Seen : FT.UString_Vectors.Vector;

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
   begin
      for Decl of Declarations loop
         if Is_Owner_Access (Decl.Type_Info) then
            declare
               Type_Name : constant String := FT.To_String (Decl.Type_Info.Name);
            begin
               if not Contains (Seen, Type_Name) then
                  Seen.Append (FT.To_UString (Type_Name));
                  Append_Line
                    (Buffer,
                     "procedure Free_"
                     & Type_Name
                     & " is new Ada.Unchecked_Deallocation ("
                     & FT.To_String (Decl.Type_Info.Target)
                     & ", "
                     & Type_Name
                     & ");",
                     Depth);
               end if;
            end;
         end if;
      end loop;
   end Render_Free_Declarations;

   procedure Render_Free_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural)
   is
      Seen : FT.UString_Vectors.Vector;
   begin
      for Decl of Declarations loop
         if Is_Owner_Access (Decl.Type_Info) then
            declare
               Type_Name : constant String := FT.To_String (Decl.Type_Info.Name);
            begin
               if not Contains_Name (Seen, Type_Name) then
                  Seen.Append (FT.To_UString (Type_Name));
                  Append_Line
                    (Buffer,
                     "procedure Free_"
                     & Type_Name
                     & " is new Ada.Unchecked_Deallocation ("
                     & FT.To_String (Decl.Type_Info.Target)
                     & ", "
                     & Type_Name
                     & ");",
                     Depth);
               end if;
            end;
         end if;
      end loop;
   end Render_Free_Declarations;

   procedure Render_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State)
   is
      Outer_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Non_Alias_Declarations (Subprogram.Declarations);
      Inner_Alias_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Alias_Declarations (Subprogram.Declarations);
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Subprogram.Declarations, Subprogram.Statements);
      Push_Cleanup_Frame (State);
      Register_Cleanup_Items (State, Outer_Declarations);
      Append_Line
        (Buffer,
         Render_Ada_Subprogram_Keyword (Subprogram)
         & " "
         & FT.To_String (Subprogram.Name)
         & Render_Subprogram_Params (Unit, Document, Subprogram.Params)
         & Render_Subprogram_Return (Subprogram)
         & " is",
         1);
      Render_Block_Declarations
        (Buffer, Unit, Document, Outer_Declarations, State, 2);
      Render_Free_Declarations (Buffer, Outer_Declarations, 2);
      Append_Line (Buffer, "begin", 1);
      Render_In_Out_Param_Stabilizers (Buffer, Subprogram, 2);
      if not Inner_Alias_Declarations.Is_Empty then
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
            (if Subprogram.Has_Return_Type then Render_Type_Name (Subprogram.Return_Type) else ""));
         Append_Line (Buffer, "end;", 2);
      else
         Render_Required_Statement_Suite
           (Buffer,
            Unit,
            Document,
            Subprogram.Statements,
            State,
            2,
            (if Subprogram.Has_Return_Type then Render_Type_Name (Subprogram.Return_Type) else ""));
      end if;
      if Statements_Fall_Through (Subprogram.Statements) then
         Render_Cleanup (Buffer, Outer_Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Subprogram.Name) & ";", 1);
      Append_Line (Buffer);
      Pop_Cleanup_Frame (State);
      Restore_Wide_Names (State, Previous_Wide_Count);
   end Render_Subprogram_Body;

   procedure Render_Task_Body
     (Buffer    : in out SU.Unbounded_String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Task_Item : CM.Resolved_Task;
      State     : in out Emit_State)
   is
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Task_Item.Declarations, Task_Item.Statements);
      Append_Line (Buffer, "task body " & FT.To_String (Task_Item.Name) & " is", 1);
      Render_Block_Declarations
        (Buffer, Unit, Document, Task_Item.Declarations, State, 2);
      Render_Free_Declarations (Buffer, Task_Item.Declarations, 2);
      Append_Line (Buffer, "begin", 1);
      Render_Required_Statement_Suite
        (Buffer, Unit, Document, Task_Item.Statements, State, 2, "");
      if Statements_Fall_Through (Task_Item.Statements) then
         Render_Cleanup (Buffer, Task_Item.Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Task_Item.Name) & ";", 1);
      Append_Line (Buffer);
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

   function Emit
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return Artifact_Result
   is
      State      : Emit_State;
      Spec_Inner : SU.Unbounded_String;
      Body_Inner : SU.Unbounded_String;
      Spec_Text  : SU.Unbounded_String;
      Body_Text  : SU.Unbounded_String;
      Body_Withs : FT.UString_Vectors.Vector;
      Synthetic_Types : GM.Type_Descriptor_Vectors.Vector;

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

      for Type_Item of Unit.Types loop
         Append_Line (Spec_Inner, Render_Type_Decl (Type_Item, State), 1);
         if FT.To_String (Type_Item.Kind) = "record" then
            Append_Line (Spec_Inner);
         end if;
      end loop;

      Collect_Synthetic_Types (Unit, Document, Synthetic_Types);
      for Type_Item of Synthetic_Types loop
         Append_Line (Spec_Inner, Render_Type_Decl (Type_Item, State), 1);
         Append_Line (Spec_Inner);
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
               & Render_Subprogram_Return (Subprogram)
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
         "package body " & FT.To_String (Unit.Package_Name) & " with SPARK_Mode => On is");
      Append_Line (Body_Inner);

      for Channel of Unit.Channels loop
         Render_Channel_Body (Body_Inner, Channel);
      end loop;

      for Subprogram of Unit.Subprograms loop
         Render_Subprogram_Body (Body_Inner, Unit, Document, Subprogram, State);
      end loop;

      for Task_Item of Unit.Tasks loop
         Render_Task_Body (Body_Inner, Unit, Document, Task_Item, State);
      end loop;

      Append_Line (Body_Inner, "end " & FT.To_String (Unit.Package_Name) & ";");

      if State.Needs_Unchecked_Deallocation then
         Add_Body_With ("Ada.Unchecked_Deallocation");
      end if;
      if State.Needs_Ada_Strings_Unbounded then
         Add_Body_With ("Ada.Strings.Unbounded");
      end if;
      if State.Needs_Safe_Runtime then
         Add_Body_With ("Safe_Runtime");
      end if;

      for Item of Body_Withs loop
         Append_Line (Body_Text, "with " & FT.To_String (Item) & ";");
      end loop;
      if State.Needs_Safe_Runtime then
         Append_Line (Body_Text, "use type Safe_Runtime.Wide_Integer;");
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
         Spec_Needs_Ada_Strings_Unbounded : constant Boolean :=
           State.Needs_Ada_Strings_Unbounded;
      begin
         if (Spec_Needs_Safe_Runtime
             or else Spec_Needs_Ada_Strings_Unbounded
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
         Needs_Safe_Runtime => State.Needs_Safe_Runtime,
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
