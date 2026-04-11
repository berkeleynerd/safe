with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;
with Safe_Frontend.Builtin_Types;
with Safe_Frontend.Name_Utils;

package body Safe_Frontend.Ada_Emit.Types is
   package BT renames Safe_Frontend.Builtin_Types;
   package FNU renames Safe_Frontend.Name_Utils;

   use AI;

   use type Ada.Containers.Count_Type;
   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type CM.Statement_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Select_Arm_Kind;
   use type FT.UString;
   use type GM.Scalar_Value_Kind;

   subtype Cleanup_Action is AI.Cleanup_Action;
   subtype Cleanup_Item is AI.Cleanup_Item;
   subtype Warning_Suppression_Array is AI.Warning_Suppression_Array;
   subtype Warning_Restore_Array is AI.Warning_Restore_Array;

   procedure Raise_Internal (Message : String) renames AI.Raise_Internal;
   procedure Raise_Unsupported
     (State   : in out Emit_State;
      Span    : FT.Source_Span;
      Message : String) renames AI.Raise_Unsupported;

   function Has_Text (Item : FT.UString) return Boolean renames AI.Has_Text;
   function Trim_Image (Value : Long_Long_Integer) return String renames AI.Trim_Image;
   function Trim_Wide_Image (Value : CM.Wide_Integer) return String renames AI.Trim_Wide_Image;
   function Indentation (Depth : Natural) return String renames AI.Indentation;
   procedure Append_Line
     (Buffer : in out SU.Unbounded_String;
      Text   : String := "";
      Depth  : Natural := 0) renames AI.Append_Line;
   function Join_Names (Items : FT.UString_Vectors.Vector) return String renames AI.Join_Names;
   function Contains_Name
     (Items : FT.UString_Vectors.Vector;
      Name  : String) return Boolean renames AI.Contains_Name;
   procedure Add_Wide_Name
     (State : in out Emit_State;
      Name  : String) renames AI.Add_Wide_Name;
   function Is_Wide_Name
     (State : Emit_State;
      Name  : String) return Boolean renames AI.Is_Wide_Name;
   function Names_Use_Wide_Storage
     (State : Emit_State;
      Names : FT.UString_Vectors.Vector) return Boolean renames AI.Names_Use_Wide_Storage;
   procedure Restore_Wide_Names
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) renames AI.Restore_Wide_Names;
   procedure Push_Type_Binding_Frame (State : in out Emit_State) renames AI.Push_Type_Binding_Frame;
   procedure Pop_Type_Binding_Frame (State : in out Emit_State) renames AI.Pop_Type_Binding_Frame;
   procedure Add_Type_Binding
     (State     : in out Emit_State;
      Name      : String;
      Type_Info : GM.Type_Descriptor) renames AI.Add_Type_Binding;
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) renames AI.Register_Type_Bindings;
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) renames AI.Register_Type_Bindings;
   procedure Register_Param_Type_Bindings
     (State  : in out Emit_State;
      Params : CM.Symbol_Vectors.Vector) renames AI.Register_Param_Type_Bindings;
   function Lookup_Bound_Type
     (State     : Emit_State;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean renames AI.Lookup_Bound_Type;
   procedure Push_Cleanup_Frame (State : in out Emit_State) renames AI.Push_Cleanup_Frame;
   procedure Pop_Cleanup_Frame (State : in out Emit_State) renames AI.Pop_Cleanup_Frame;
   procedure Add_Cleanup_Item
     (State     : in out Emit_State;
      Name      : String;
      Type_Name : String;
      Free_Proc : String := "";
      Is_Constant : Boolean := False;
      Always_Terminates_Suppression_OK : Boolean := False;
      Action    : Cleanup_Action := AI.Cleanup_Deallocate) renames AI.Add_Cleanup_Item;
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) renames AI.Register_Cleanup_Items;
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) renames AI.Register_Cleanup_Items;
   procedure Render_Cleanup_Item
     (Buffer : in out SU.Unbounded_String;
      Item   : Cleanup_Item;
      Depth  : Natural) renames AI.Render_Cleanup_Item;
   procedure Render_Active_Cleanup
     (Buffer    : in out SU.Unbounded_String;
      State     : Emit_State;
      Depth     : Natural;
      Skip_Name : String := "") renames AI.Render_Active_Cleanup;
   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural) renames AI.Render_Current_Cleanup_Frame;
   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean renames AI.Has_Active_Cleanup_Items;
   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural) renames AI.Render_Cleanup;
   function Statement_Falls_Through (Item : CM.Statement_Access) return Boolean renames AI.Statement_Falls_Through;
   function Statements_Fall_Through (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Fall_Through;
   function Statement_Contains_Exit (Item : CM.Statement_Access) return Boolean renames AI.Statement_Contains_Exit;
   function Statements_Contain_Exit (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Contain_Exit;
   procedure Append_Gnatprove_Warning_Suppression
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Reason  : String;
      Depth   : Natural) renames AI.Append_Gnatprove_Warning_Suppression;
   procedure Append_Gnatprove_Warning_Restore
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Depth   : Natural) renames AI.Append_Gnatprove_Warning_Restore;
   procedure Append_Gnatprove_Warning_Suppressions
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Suppression_Array;
      Depth    : Natural) renames AI.Append_Gnatprove_Warning_Suppressions;
   procedure Append_Gnatprove_Warning_Restores
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Restore_Array;
      Depth    : Natural) renames AI.Append_Gnatprove_Warning_Restores;
   procedure Append_Initialization_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Initialization_Warning_Suppression;
   procedure Append_Initialization_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Initialization_Warning_Restore;
   procedure Append_Local_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Local_Warning_Suppression;
   procedure Append_Local_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Local_Warning_Restore;
   procedure Append_Channel_Staged_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Channel_Staged_Call_Warning_Suppression;
   procedure Append_Channel_Staged_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Channel_Staged_Call_Warning_Restore;
   procedure Append_Task_Assignment_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Assignment_Warning_Suppression;
   procedure Append_Task_Assignment_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Assignment_Warning_Restore;
   procedure Append_Task_If_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_If_Warning_Suppression;
   procedure Append_Task_If_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_If_Warning_Restore;
   procedure Append_Task_Channel_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Channel_Call_Warning_Suppression;
   procedure Append_Task_Channel_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Channel_Call_Warning_Restore;

   function Starts_With (Text : String; Prefix : String) return Boolean renames AI.Starts_With;
   function Sanitized_Helper_Name (Name : String) return String;

   function Binary_Width_From_Name (Name : String) return Natural;
   function Is_Builtin_Binary_Name (Name : String) return Boolean;
   function Type_Info_From_Name_Or_Synthetic
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Local_Free_Helper_Name (Info : GM.Type_Descriptor) return String;
   function For_Of_Helper_Base_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Local_Dispose_Helper_Name (Info : GM.Type_Descriptor) return String;
   function Local_Ownership_Runtime_Name (Info : GM.Type_Descriptor) return String;
   function Array_Runtime_Default_Element_Name (Info : GM.Type_Descriptor) return String;
   function Array_Runtime_Clone_Element_Name (Info : GM.Type_Descriptor) return String;
   function Render_Integer_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Enum_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Binary_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Subtype_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor) return String;
   function Render_Nominal_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Array_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Tuple_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Result_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Record_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Access_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Float_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;

   procedure Append_Record_Heap_Copy_Assignments
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Target_Prefix : String;
      Source_Prefix : String;
      Depth       : Natural)
   ;
   procedure Append_Record_Heap_Free_Statements
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Value_Prefix : String;
      Depth       : Natural)
   ;
   function Array_Runtime_Generic_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   ;
   function Array_Runtime_Identity_Ops_Name
     (Info : GM.Type_Descriptor) return String;

   function Same_Variant_Choice
     (Left, Right : GM.Variant_Field) return Boolean;

   function Binary_Ada_Name (Bit_Width : Positive) return String is
   begin
      return
        "Interfaces.Unsigned_"
        & Ada.Strings.Fixed.Trim (Positive'Image (Bit_Width), Ada.Strings.Both);
   end Binary_Ada_Name;

   function Ada_Safe_Name (Name : String) return String is
      Bit_Width : constant Natural := Binary_Width_From_Name (Name);
      function Collapse_Underscores (Text : String) return String is
         Result          : SU.Unbounded_String;
         Last_Underscore : Boolean := False;
      begin
         for Ch of Text loop
            if Ch = '_' then
               if not Last_Underscore then
                  Result := Result & "_";
               end if;
               Last_Underscore := True;
            else
               Result := Result & Ch;
               Last_Underscore := False;
            end if;
         end loop;
         return SU.To_String (Result);
      end Collapse_Underscores;
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
         return
           "Safe_"
           & Collapse_Underscores (Name (Name'First + 2 .. Name'Last));
      elsif Name'Length > 0 and then Name (Name'First) = '_' then
         return "Safe" & Name;
      end if;
      return Name;
   end Ada_Safe_Name;

   function Ada_Qualified_Name (Name : String) return String is
      Dot : constant Natural := Ada.Strings.Fixed.Index (Name, ".");
   begin
      if Dot = 0 then
         return Ada_Safe_Name (Name);
      elsif Dot = Name'First then
         return Ada_Qualified_Name (Name (Dot + 1 .. Name'Last));
      elsif Dot = Name'Last then
         return Ada_Qualified_Name (Name (Name'First .. Dot - 1));
      end if;

      return
        Ada_Qualified_Name (Name (Name'First .. Dot - 1))
        & "."
        & Ada_Qualified_Name (Name (Dot + 1 .. Name'Last));
   end Ada_Qualified_Name;

   function Render_Enum_Literal_Name
     (Literal_Name   : String;
      Enum_Type_Name : String) return String
   is
      Literal_Dot : constant Natural := Ada.Strings.Fixed.Index (Literal_Name, ".");
      Type_Dot    : constant Natural :=
        Ada.Strings.Fixed.Index
          (Enum_Type_Name,
           ".",
           Going => Ada.Strings.Backward);
   begin
      if Literal_Dot > 0 then
         return Ada_Qualified_Name (Literal_Name);
      elsif Type_Dot > 0 then
         return
           Ada_Qualified_Name (Enum_Type_Name (Enum_Type_Name'First .. Type_Dot - 1))
           & "."
           & Ada_Safe_Name (Literal_Name);
      end if;

      return Ada_Safe_Name (Literal_Name);
   end Render_Enum_Literal_Name;

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
         if FT.To_String (Item.Name) = Name
           or else Ada_Safe_Name (FT.To_String (Item.Name)) = Name
         then
            return Item;
         end if;
      end loop;
      for Item of Unit.Imported_Types loop
         if FT.To_String (Item.Name) = Name
           or else Ada_Safe_Name (FT.To_String (Item.Name)) = Name
         then
            return Item;
         end if;
      end loop;
      for Item of Document.Types loop
         if FT.To_String (Item.Name) = Name
           or else Ada_Safe_Name (FT.To_String (Item.Name)) = Name
         then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Lookup_Type;

   function Base_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor := Preferred_Imported_Synthetic_Type (Unit, Info);
   begin
      while FT.To_String (Result.Kind) in "subtype" | "nominal"
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
         return Type_Info_From_Name_Or_Synthetic
           (Unit, Document, FT.To_String (Base.Target), Type_Info);
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
                 Type_Info_From_Name_Or_Synthetic
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
              Type_Info_From_Name_Or_Synthetic
                (Unit,
                 Document,
                 FT.To_String (Base.Discriminant_Type),
                 Type_Info);
         end if;

         for Field of Base.Fields loop
            if FT.To_String (Field.Name) = Selector then
               return
                 Type_Info_From_Name_Or_Synthetic
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
                       Type_Info_From_Name_Or_Synthetic
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

   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean renames AI.Is_Access_Type;
   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean renames AI.Is_Owner_Access;

   function Owner_Allocate_Post_Field_Is_Trackable
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Field_Info : GM.Type_Descriptor) return Boolean
   is
      Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Field_Info);
      Base_Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
      Base_Name : constant String := FT.Lowercase (FT.To_String (Base.Name));
   begin
      return
        not Is_Access_Type (Field_Info)
        and then not Has_Heap_Value_Type (Unit, Document, Field_Info)
        and then
          (Is_Integer_Type (Unit, Document, Field_Info)
           or else Base_Kind = "boolean"
           or else Base_Name = "boolean"
           or else Base_Kind = "enum"
           or else Base_Kind = "character"
           or else Base_Name = "character");
   end Owner_Allocate_Post_Field_Is_Trackable;

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

   function Try_Map_Key_Value_Types
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Info       : GM.Type_Descriptor;
      Key_Type   : out GM.Type_Descriptor;
      Value_Type : out GM.Type_Descriptor) return Boolean
   is
      Base       : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Entry_Type : GM.Type_Descriptor := (others => <>);
   begin
      Key_Type := (others => <>);
      Value_Type := (others => <>);

      if not Is_Growable_Array_Type (Unit, Document, Base)
        or else not Base.Has_Component_Type
      then
         return False;
      end if;

      Entry_Type :=
        Base_Type
          (Unit,
           Document,
           Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type)));
      if FT.Lowercase (FT.To_String (Entry_Type.Kind)) /= "tuple"
        or else Natural (Entry_Type.Tuple_Element_Types.Length) /= 2
      then
         return False;
      end if;

      Key_Type :=
        Resolve_Type_Name
          (Unit,
           Document,
           FT.To_String
             (Entry_Type.Tuple_Element_Types (Entry_Type.Tuple_Element_Types.First_Index)));
      Value_Type :=
        Resolve_Type_Name
          (Unit,
           Document,
           FT.To_String
             (Entry_Type.Tuple_Element_Types (Entry_Type.Tuple_Element_Types.First_Index + 1)));
      return True;
   end Try_Map_Key_Value_Types;

   function Constant_Cleanup_Uses_Shared_Runtime_Free
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor;
      Free_Proc : String) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      if Is_Plain_String_Type (Unit, Document, Info) then
         return Free_Proc = "Safe_String_RT.Free";
      end if;

      if Is_Growable_Array_Type (Unit, Document, Info) then
         return Free_Proc = Array_Runtime_Instance_Name (Info) & ".Free"
           or else Free_Proc = Array_Runtime_Instance_Name (Base) & ".Free";
      end if;

      return False;
   end Constant_Cleanup_Uses_Shared_Runtime_Free;

   function Sanitized_Helper_Name (Name : String) return String renames AI.Sanitized_Helper_Name;

   function Needs_Generated_For_Of_Helper
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
   begin
      return Has_Heap_Value_Type (Unit, Document, Base)
        and then not Is_Plain_String_Type (Unit, Document, Base)
        and then not Is_Growable_Array_Type (Unit, Document, Base)
        and then (Kind = "array" or else Kind = "record" or else Is_Tuple_Type (Base));
   end Needs_Generated_For_Of_Helper;

   function For_Of_Copy_Helper_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
   begin
      return For_Of_Helper_Base_Name (Unit, Document, Info) & "_Copy";
   end For_Of_Copy_Helper_Name;

   function For_Of_Free_Helper_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
   begin
      return For_Of_Helper_Base_Name (Unit, Document, Info) & "_Free";
   end For_Of_Free_Helper_Name;

   function Needs_Generated_Heap_Helper
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
   begin
      return Has_Heap_Value_Type (Unit, Document, Base)
        and then not Is_Plain_String_Type (Unit, Document, Base)
        and then not Is_Growable_Array_Type (Unit, Document, Base)
        and then (Kind = "array" or else Kind = "record" or else Is_Tuple_Type (Base));
   end Needs_Generated_Heap_Helper;

   function Heap_Helper_Base_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String
   is
      pragma Unreferenced (Document);
   begin
      case Family is
         when AI.Heap_Helper_Shared | AI.Heap_Helper_Channel =>
            return Scope_Name & "_" & Sanitized_Helper_Name (Render_Type_Name (Info));
         when AI.Heap_Helper_For_Of =>
            return For_Of_Helper_Base_Name (Unit, Document, Info);
      end case;
   end Heap_Helper_Base_Name;

   function Heap_Copy_Helper_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String
   is
   begin
      return Heap_Helper_Base_Name (Family, Scope_Name, Unit, Document, Info) & "_Copy";
   end Heap_Copy_Helper_Name;

   function Heap_Free_Helper_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String
   is
   begin
      return Heap_Helper_Base_Name (Family, Scope_Name, Unit, Document, Info) & "_Free";
   end Heap_Free_Helper_Name;

   procedure Append_Heap_Copy_Value
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Family     : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Target_Text : String;
      Source_Text : String;
      Info       : GM.Type_Descriptor;
      Depth      : Natural)
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      if Is_Plain_String_Type (Unit, Document, Base) then
         Append_Line
           (Buffer,
            Target_Text & " := Safe_String_RT.Clone (" & Source_Text & ");",
            Depth);
      elsif Is_Growable_Array_Type (Unit, Document, Base) then
         Append_Line
           (Buffer,
            Target_Text
            & " := "
            & Array_Runtime_Instance_Name (Base)
            & ".Clone ("
            & Source_Text
            & ");",
            Depth);
      elsif Needs_Generated_Heap_Helper (Unit, Document, Info) then
         Append_Line
           (Buffer,
            Heap_Copy_Helper_Name (Family, Scope_Name, Unit, Document, Info)
            & " ("
            & Target_Text
            & ", "
            & Source_Text
            & ");",
            Depth);
      else
         Append_Line (Buffer, Target_Text & " := " & Source_Text & ";", Depth);
      end if;
   end Append_Heap_Copy_Value;

   procedure Append_Heap_Free_Value
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Family     : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Target_Text : String;
      Info       : GM.Type_Descriptor;
      Depth      : Natural)
   is
      pragma Unreferenced (State);
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      if Is_Plain_String_Type (Unit, Document, Base) then
         Append_Line (Buffer, "Safe_String_RT.Free (" & Target_Text & ");", Depth);
      elsif Is_Growable_Array_Type (Unit, Document, Base) then
         Append_Line
           (Buffer,
            Array_Runtime_Instance_Name (Base) & ".Free (" & Target_Text & ");",
            Depth);
      elsif Needs_Generated_Heap_Helper (Unit, Document, Info) then
         Append_Line
           (Buffer,
            Heap_Free_Helper_Name (Family, Scope_Name, Unit, Document, Info)
            & " ("
            & Target_Text
            & ");",
            Depth);
      end if;
   end Append_Heap_Free_Value;

   function Array_Runtime_Instance_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_RT";
   end Array_Runtime_Instance_Name;

   function Array_Runtime_Free_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_Free_Element";
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

      function Find_Local_Synthetic_Type
        (Target_Name : String;
         Found       : out Boolean) return GM.Type_Descriptor
      is
         Match : GM.Type_Descriptor := (others => <>);

         procedure Check_Info (Info : GM.Type_Descriptor);
         procedure Check_Expr (Expr : CM.Expr_Access);
         procedure Check_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector);
         procedure Check_Decls (Decls : CM.Object_Decl_Vectors.Vector);
         procedure Check_Statements
           (Statements : CM.Statement_Access_Vectors.Vector);

         procedure Check_Info (Info : GM.Type_Descriptor) is
         begin
            if Found or else not Has_Text (Info.Name) then
               return;
            end if;

            if FT.To_String (Info.Name) = Target_Name then
               if Starts_With (Target_Name, "__tuple")
                 and then Info.Tuple_Element_Types.Is_Empty
               then
                  return;
               end if;
               Match := Info;
               Found := True;
            end if;
         end Check_Info;

         procedure Check_Expr (Expr : CM.Expr_Access) is
         begin
            if Found or else Expr = null then
               return;
            end if;

            if Expr.Kind = CM.Expr_Tuple
              and then Has_Text (Expr.Type_Name)
              and then FT.To_String (Expr.Type_Name) = Target_Name
            then
               Match.Name := Expr.Type_Name;
               Match.Kind := FT.To_UString ("tuple");
               for Element of Expr.Elements loop
                  if Element /= null and then Has_Text (Element.Type_Name) then
                     Match.Tuple_Element_Types.Append (Element.Type_Name);
                  end if;
               end loop;
               Found := True;
               return;
            end if;

            Check_Expr (Expr.Prefix);
            Check_Expr (Expr.Callee);
            Check_Expr (Expr.Inner);
            Check_Expr (Expr.Left);
            Check_Expr (Expr.Right);
            Check_Expr (Expr.Value);
            Check_Expr (Expr.Target);
            for Item of Expr.Args loop
               exit when Found;
               Check_Expr (Item);
            end loop;
            for Item of Expr.Elements loop
               exit when Found;
               Check_Expr (Item);
            end loop;
            for Field of Expr.Fields loop
               exit when Found;
               Check_Expr (Field.Expr);
            end loop;
         end Check_Expr;

         procedure Check_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector) is
         begin
            for Decl of Decls loop
               Check_Info (Decl.Type_Info);
               exit when Found;
               Check_Expr (Decl.Initializer);
               exit when Found;
            end loop;
         end Check_Decls;

         procedure Check_Decls (Decls : CM.Object_Decl_Vectors.Vector) is
         begin
            for Decl of Decls loop
               Check_Info (Decl.Type_Info);
               exit when Found;
               Check_Expr (Decl.Initializer);
               exit when Found;
            end loop;
         end Check_Decls;

         procedure Check_Statements
           (Statements : CM.Statement_Access_Vectors.Vector)
         is
         begin
            for Item of Statements loop
               exit when Found;
               if Item = null then
                  null;
               else
                  case Item.Kind is
                     when CM.Stmt_Object_Decl =>
                        Check_Info (Item.Decl.Type_Info);
                        Check_Expr (Item.Decl.Initializer);
                     when CM.Stmt_Destructure_Decl =>
                        Check_Info (Item.Destructure.Type_Info);
                        Check_Expr (Item.Destructure.Initializer);
                     when CM.Stmt_If =>
                        Check_Expr (Item.Condition);
                        Check_Statements (Item.Then_Stmts);
                        for Part of Item.Elsifs loop
                           exit when Found;
                           Check_Expr (Part.Condition);
                           Check_Statements (Part.Statements);
                        end loop;
                        if Item.Has_Else then
                           Check_Statements (Item.Else_Stmts);
                        end if;
                     when CM.Stmt_Case =>
                        Check_Expr (Item.Case_Expr);
                        for Arm of Item.Case_Arms loop
                           exit when Found;
                           Check_Expr (Arm.Choice);
                           Check_Statements (Arm.Statements);
                        end loop;
                     when CM.Stmt_While | CM.Stmt_Loop | CM.Stmt_For =>
                        Check_Expr (Item.Condition);
                        Check_Expr (Item.Loop_Iterable);
                        Check_Expr (Item.Loop_Range.Low_Expr);
                        Check_Expr (Item.Loop_Range.High_Expr);
                        Check_Decls (Item.Declarations);
                        Check_Statements (Item.Body_Stmts);
                     when CM.Stmt_Select =>
                        for Arm of Item.Arms loop
                           exit when Found;
                           case Arm.Kind is
                              when CM.Select_Arm_Channel =>
                                 Check_Info (Arm.Channel_Data.Type_Info);
                                 Check_Expr (Arm.Channel_Data.Channel_Name);
                                 Check_Statements (Arm.Channel_Data.Statements);
                              when CM.Select_Arm_Delay =>
                                 Check_Expr (Arm.Delay_Data.Duration_Expr);
                                 Check_Statements (Arm.Delay_Data.Statements);
                              when others =>
                                 null;
                           end case;
                        end loop;
                     when others =>
                        Check_Expr (Item.Target);
                        Check_Expr (Item.Value);
                        Check_Expr (Item.Call);
                        Check_Expr (Item.Condition);
                        Check_Expr (Item.Case_Expr);
                        Check_Expr (Item.Match_Expr);
                        Check_Expr (Item.Channel_Name);
                        Check_Expr (Item.Success_Var);
                  end case;
               end if;
            end loop;
         end Check_Statements;
      begin
         Found := False;

         for Item of Unit.Types loop
            Check_Info (Item);
            exit when Found;
         end loop;
         for Item of Unit.Objects loop
            exit when Found;
            Check_Info (Item.Type_Info);
         end loop;
         for Item of Unit.Channels loop
            exit when Found;
            Check_Info (Item.Element_Type);
         end loop;
         for Item of Unit.Subprograms loop
            exit when Found;
            for Param of Item.Params loop
               Check_Info (Param.Type_Info);
               exit when Found;
            end loop;
            if not Found and then Item.Has_Return_Type then
               Check_Info (Item.Return_Type);
            end if;
            if not Found then
               Check_Decls (Item.Declarations);
               Check_Statements (Item.Statements);
            end if;
         end loop;
         for Item of Unit.Tasks loop
            exit when Found;
            Check_Decls (Item.Declarations);
            Check_Statements (Item.Statements);
         end loop;
         if not Found then
            Check_Statements (Unit.Statements);
         end if;

         return Match;
      end Find_Local_Synthetic_Type;
   begin
      if Name'Length = 0 then
         return (others => <>);
      end if;

      if Has_Type (Unit, Document, Name) then
         return Lookup_Type (Unit, Document, Name);
      elsif Starts_With (Name, "__tuple") then
         declare
            Found_Local_Synthetic : Boolean := False;
         begin
            Result := Find_Local_Synthetic_Type (Name, Found_Local_Synthetic);
            if Found_Local_Synthetic then
               return Result;
            end if;
         end;
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

   function Render_Type_Name (Info : GM.Type_Descriptor) return String is
      Result : SU.Unbounded_String;
   begin
      if Info.Anonymous and then Is_Access_Type (Info) then
         return
           (if Info.Not_Null then "not null " else "")
           & "access "
           & (if Info.Is_Constant then "constant " else "")
           & Ada_Qualified_Name (FT.To_String (Info.Target));
      elsif FT.To_String (Info.Kind) = "subtype"
        and then not Info.Discriminant_Constraints.Is_Empty
        and then not Starts_With (FT.To_String (Info.Name), "__constraint")
      then
         Result :=
           SU.To_Unbounded_String
             (Ada_Qualified_Name
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
                        (Ada_Safe_Name (FT.To_String (Constraint.Name)) & " => ");
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
         return Ada_Qualified_Name (FT.To_String (Info.Name));
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
      return Ada_Qualified_Name (FT.To_String (Info.Name));
   end Render_Type_Name;

   function Render_Type_Name_From_Text
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name_Text : String;
      State     : in out Emit_State) return String
   is
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
      elsif Has_Type (Unit, Document, Name_Text) then
         return Render_Type_Name (Lookup_Type (Unit, Document, Name_Text));
      end if;

      return Ada_Safe_Name (Name_Text);
   end Render_Type_Name_From_Text;

   function Render_Subtype_Indication
     (Unit     : CM.Resolved_Unit;
     Document : GM.Mir_Document;
     Info     : GM.Type_Descriptor) return String
   is
      Preferred_Info : constant GM.Type_Descriptor :=
        Preferred_Imported_Synthetic_Type (Unit, Info);
      Base_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Preferred_Info);
      Base_Name : constant String := Render_Type_Name (Preferred_Info);
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
         return
           Render_Type_Name
             (Preferred_Imported_Synthetic_Type
                (Unit,
                 Lookup_Type (Unit, Document, Name)));
      end if;
      return Ada_Qualified_Name (Name);
   end Render_Type_Name;

   function Default_Value_Expr (Type_Name : String) return String is
   begin
      if Type_Name = "boolean" then
         return "false";
      elsif Type_Name = "string" then
         return "Safe_String_RT.Empty";
      elsif Type_Name = "float" or else Type_Name = "long_float" then
         return "0.0";
      elsif Starts_With (Type_Name, "__growable_array_")
        or else Starts_With (Type_Name, "Safe_growable_array_")
      then
         return Ada_Qualified_Name (Type_Name) & "_RT.Empty";
      elsif Starts_With (Type_Name, "access ")
        or else Starts_With (Type_Name, "not null access ")
        or else Starts_With (Type_Name, "access constant ")
        or else Starts_With (Type_Name, "not null access constant ")
      then
         return "null";
      end if;
      return Ada_Qualified_Name (Type_Name) & "'First";
   end Default_Value_Expr;

   function Default_Value_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
      Preferred_Info : constant GM.Type_Descriptor :=
        Preferred_Imported_Synthetic_Type (Unit, Info);
      Type_Name : constant String := Render_Type_Name (Preferred_Info);
      Kind      : constant String := FT.To_String (Preferred_Info.Kind);
      Result    : SU.Unbounded_String;
   begin
      if Is_Bounded_String_Type (Preferred_Info) then
         return Bounded_String_Instance_Name (Preferred_Info) & ".Empty";
      elsif FT.Lowercase (Kind) = "string" then
         return "Safe_String_RT.Empty";
      elsif FT.Lowercase (Kind) = "array" and then Preferred_Info.Growable then
         return Array_Runtime_Instance_Name (Preferred_Info) & ".Empty";
      elsif Kind = "access" then
         return "null";
      elsif Kind = "array" and then not Preferred_Info.Index_Types.Is_Empty then
         Result := SU.To_Unbounded_String ("");
         for Index in 1 .. Natural (Preferred_Info.Index_Types.Length) loop
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
                      FT.To_String (Preferred_Info.Component_Type))));
         for Index in 1 .. Natural (Preferred_Info.Index_Types.Length) loop
            Result := Result & SU.To_Unbounded_String (")");
         end loop;
         return SU.To_String (Result);
      elsif Is_Result_Builtin (Preferred_Info) then
         return Render_Result_Empty_Aggregate;
      elsif Kind = "record"
        or else
          (Kind = "subtype"
           and then not Info.Discriminant_Constraints.Is_Empty
           and then FT.To_String (Base_Type (Unit, Document, Info).Kind) = "record")
      then
         declare
            Base_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
            Qualified_Name : constant String :=
              (if Kind = "subtype"
               then Render_Type_Name (Base_Info)
               elsif Has_Text (Info.Name)
               then Render_Type_Name (Preferred_Info)
               else Render_Type_Name (Info));
            First_Association : Boolean := True;
            Disc_Name : constant String :=
              FT.To_String
                ((if Has_Text (Base_Info.Variant_Discriminant_Name)
                  then Base_Info.Variant_Discriminant_Name
                  else Base_Info.Discriminant_Name));

            procedure Append_Association (Name, Value : String) is
            begin
               if not First_Association then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result & SU.To_Unbounded_String (Name & " => " & Value);
               First_Association := False;
            end Append_Association;

            function Is_Variant_Field_Name (Field_Name : String) return Boolean is
            begin
               for Field of Base_Info.Variant_Fields loop
                  if FT.To_String (Field.Name) = Field_Name then
                     return True;
                  end if;
               end loop;
               return False;
            end Is_Variant_Field_Name;

            function Selected_Variant_Choice return String is
            begin
               if Disc_Name'Length = 0 then
                  return "";
               elsif Kind = "subtype" then
                  for Constraint of Info.Discriminant_Constraints loop
                     if (Constraint.Is_Named and then FT.To_String (Constraint.Name) = Disc_Name)
                       or else (not Constraint.Is_Named and then Info.Discriminant_Constraints.Length = 1)
                     then
                        return Render_Scalar_Value (Constraint.Value);
                     end if;
                  end loop;
               else
                  for Disc of Base_Info.Discriminants loop
                     if FT.To_String (Disc.Name) = Disc_Name and then Disc.Has_Default then
                        return Render_Scalar_Value (Disc.Default_Value);
                     end if;
                  end loop;
                  if Base_Info.Discriminants.Is_Empty
                    and then Base_Info.Has_Discriminant
                    and then FT.To_String (Base_Info.Discriminant_Name) = Disc_Name
                    and then Base_Info.Has_Discriminant_Default
                  then
                     return (if Base_Info.Discriminant_Default_Bool then "true" else "false");
                  end if;
               end if;
               return "";
            end Selected_Variant_Choice;

            function Exact_Variant_Choice_Match return Boolean is
               Choice_Image : constant String := Selected_Variant_Choice;
            begin
               if Choice_Image'Length = 0 then
                  return False;
               end if;
               for Field of Base_Info.Variant_Fields loop
                  if not Field.Is_Others
                    and then Render_Scalar_Value (Field.Choice) = Choice_Image
                  then
                     return True;
                  end if;
               end loop;
               return False;
            end Exact_Variant_Choice_Match;

            function Variant_Field_Is_Active (Field : GM.Variant_Field) return Boolean is
               Choice_Image : constant String := Selected_Variant_Choice;
            begin
               if Choice_Image'Length = 0 then
                  return False;
               elsif Field.Is_Others then
                  return not Exact_Variant_Choice_Match;
               else
                  return Render_Scalar_Value (Field.Choice) = Choice_Image;
               end if;
            end Variant_Field_Is_Active;
         begin
            Result := SU.To_Unbounded_String (Qualified_Name & "'(");
            if Kind = "subtype" then
               for Constraint of Info.Discriminant_Constraints loop
                  if not First_Association then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        ((if Constraint.Is_Named
                          then Ada_Safe_Name (FT.To_String (Constraint.Name)) & " => "
                          else "")
                         & Render_Scalar_Value (Constraint.Value));
                  First_Association := False;
               end loop;
            elsif Kind = "record" then
               for Disc of Base_Info.Discriminants loop
                  if Disc.Has_Default then
                     Append_Association
                       (Ada_Safe_Name (FT.To_String (Disc.Name)),
                        Render_Scalar_Value (Disc.Default_Value));
                  end if;
               end loop;
               if Base_Info.Discriminants.Is_Empty
                 and then Base_Info.Has_Discriminant
                 and then Base_Info.Has_Discriminant_Default
               then
                  Append_Association
                    (Ada_Safe_Name (FT.To_String (Base_Info.Discriminant_Name)),
                     (if Base_Info.Discriminant_Default_Bool then "true" else "false"));
               end if;
            end if;

            for Index in Base_Info.Fields.First_Index .. Base_Info.Fields.Last_Index loop
               declare
                  Field_Name : constant String := FT.To_String (Base_Info.Fields (Index).Name);
               begin
                  if not Is_Variant_Field_Name (Field_Name) then
                     Append_Association
                       (Ada_Safe_Name (Field_Name),
                        Default_Value_Expr
                          (Unit,
                           Document,
                           Resolve_Type_Name
                             (Unit,
                              Document,
                              FT.To_String (Base_Info.Fields (Index).Type_Name))));
                  end if;
               end;
            end loop;

            for Field of Base_Info.Variant_Fields loop
               if Variant_Field_Is_Active (Field) then
                  Append_Association
                    (Ada_Safe_Name (FT.To_String (Field.Name)),
                     Default_Value_Expr
                       (Unit,
                        Document,
                        Resolve_Type_Name
                          (Unit,
                           Document,
                           FT.To_String (Field.Type_Name))));
               end if;
            end loop;

            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         end;
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
      elsif Is_Result_Builtin (Info) then
         return Render_Result_Empty_Aggregate;
      elsif Kind = "record"
        or else (Kind = "subtype" and then not Info.Discriminant_Constraints.Is_Empty)
      then
         declare
            Qualified_Name : constant String :=
              (if Kind = "subtype" and then Info.Has_Base
               then Ada_Safe_Name (FT.To_String (Info.Base))
               elsif Has_Text (Info.Name)
               then Ada_Safe_Name (FT.To_String (Info.Name))
               else Type_Name);
            First_Association : Boolean := True;

            procedure Append_Association (Name, Value : String) is
            begin
               if not First_Association then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result & SU.To_Unbounded_String (Name & " => " & Value);
               First_Association := False;
            end Append_Association;
         begin
            Result := SU.To_Unbounded_String (Qualified_Name & "'(");
            if Kind = "subtype" then
               for Constraint of Info.Discriminant_Constraints loop
                  if not First_Association then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        ((if Constraint.Is_Named
                          then Ada_Safe_Name (FT.To_String (Constraint.Name)) & " => "
                          else "")
                         & Render_Scalar_Value (Constraint.Value));
                  First_Association := False;
               end loop;
            elsif Kind = "record" then
               for Disc of Info.Discriminants loop
                  if Disc.Has_Default then
                     Append_Association
                       (Ada_Safe_Name (FT.To_String (Disc.Name)),
                        Render_Scalar_Value (Disc.Default_Value));
                  end if;
               end loop;
               if Info.Discriminants.Is_Empty
                 and then Info.Has_Discriminant
                 and then Info.Has_Discriminant_Default
               then
                  Append_Association
                    (Ada_Safe_Name (FT.To_String (Info.Discriminant_Name)),
                     (if Info.Discriminant_Default_Bool then "true" else "false"));
               end if;
            end if;

            for Index in Info.Fields.First_Index .. Info.Fields.Last_Index loop
               Append_Association
                 (Ada_Safe_Name (FT.To_String (Info.Fields (Index).Name)),
                  Default_Value_Expr (FT.To_String (Info.Fields (Index).Type_Name)));
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         end;
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
      end if;
      return Default_Value_Expr (Type_Name);
   end Default_Value_Expr;

   function Needs_Explicit_Default_Initializer
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind      : constant String := FT.Lowercase (FT.To_String (Base_Info.Kind));
      Name      : constant String := FT.Lowercase (FT.To_String (Base_Info.Name));
   begin
      if Is_Bounded_String_Type (Base_Info)
        or else Kind = "string"
        or else (Kind = "array" and then Base_Info.Growable)
        or else Kind = "access"
        or else Is_Result_Builtin (Base_Info)
      then
         return False;
      elsif Kind = "integer"
        or else Kind = "binary"
        or else Kind = "float"
        or else Name = "boolean"
      then
         return True;
      elsif Kind = "array" and then not Base_Info.Index_Types.Is_Empty then
         return
           Needs_Explicit_Default_Initializer
             (Unit,
              Document,
              Resolve_Type_Name
                (Unit,
                 Document,
                 FT.To_String (Base_Info.Component_Type)));
      elsif Kind = "record" then
         for Field of Base_Info.Fields loop
            if Needs_Explicit_Default_Initializer
              (Unit,
               Document,
               Resolve_Type_Name
                 (Unit, Document, FT.To_String (Field.Type_Name)))
            then
               return True;
            end if;
         end loop;
         return False;
      elsif Is_Tuple_Type (Base_Info) then
         for Element_Type of Base_Info.Tuple_Element_Types loop
            if Needs_Explicit_Default_Initializer
              (Unit,
               Document,
               Resolve_Type_Name (Unit, Document, FT.To_String (Element_Type)))
            then
               return True;
            end if;
         end loop;
         return False;
      end if;

      return False;
   end Needs_Explicit_Default_Initializer;

   procedure Collect_Synthetic_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector)
   is
      Seen      : FT.UString_Vectors.Vector;
      Processed : FT.UString_Vectors.Vector;

      procedure Add_From_Info (Info : GM.Type_Descriptor);
      procedure Add_From_Statements (Statements : CM.Statement_Access_Vectors.Vector);

      function Synthetic_Optional_Type
        (Element_Info : GM.Type_Descriptor) return GM.Type_Descriptor
      is
         Result  : GM.Type_Descriptor;
         Disc    : GM.Discriminant_Descriptor;
         Field   : GM.Type_Field;
         Variant : GM.Variant_Field;
      begin
         Result.Name :=
           FT.To_UString
             ("__optional_"
              & Sanitize_Type_Name_Component (FT.To_String (Element_Info.Name)));
         Result.Kind := FT.To_UString ("record");
         Result.Has_Discriminant := True;
         Result.Discriminant_Name := FT.To_UString ("present");
         Result.Discriminant_Type := FT.To_UString ("boolean");
         Result.Has_Discriminant_Default := True;
         Result.Discriminant_Default_Bool := False;

         Disc.Name := FT.To_UString ("present");
         Disc.Type_Name := FT.To_UString ("boolean");
         Disc.Has_Default := True;
         Disc.Default_Value.Kind := GM.Scalar_Value_Boolean;
         Disc.Default_Value.Bool_Value := False;
         Result.Discriminants.Append (Disc);

         Field.Name := FT.To_UString ("value");
         Field.Type_Name := Element_Info.Name;
         Result.Fields.Append (Field);

         Variant.Name := FT.To_UString ("value");
         Variant.Type_Name := Element_Info.Name;
         Variant.Choice.Kind := GM.Scalar_Value_Boolean;
         Variant.Choice.Bool_Value := True;
         Variant.When_True := True;
         Result.Variant_Discriminant_Name := FT.To_UString ("present");
         Result.Variant_Fields.Append (Variant);
         return Result;
      end Synthetic_Optional_Type;

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
         elsif Starts_With (Name, "__growable_array_") then
            Add_From_Info (Resolve_Type_Name (Unit, Document, Name));
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
            Add_From_Info (Resolve_Type_Name (Unit, Document, Name));
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

         if Starts_With (Name_Text, "__optional_")
           or else (FT.To_String (Info.Kind) = "array" and then Info.Growable)
           or else (FT.To_String (Info.Kind) = "subtype" and then not Info.Discriminant_Constraints.Is_Empty)
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
         if Item.Generic_Formals.Is_Empty
           and then Has_Text (Item.Name)
           and then not Contains_Name (Seen, FT.To_String (Item.Name))
         then
            Seen.Append (Item.Name);
         end if;
      end loop;
      for Item of Unit.Imported_Types loop
         if Has_Text (Item.Name)
           and then not Contains_Name (Seen, FT.To_String (Item.Name))
         then
            Seen.Append (Item.Name);
         end if;
      end loop;

      for Item of Unit.Types loop
         if Item.Generic_Formals.Is_Empty then
            Add_From_Info (Item);
         end if;
      end loop;
      for Item of Unit.Objects loop
         Add_From_Info (Item.Type_Info);
         if Item.Is_Shared and then Is_Growable_Array_Type (Unit, Document, Item.Type_Info) then
            declare
               Element_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Base_Type (Unit, Document, Item.Type_Info).Component_Type));
               Key_Info     : GM.Type_Descriptor := (others => <>);
               Value_Info   : GM.Type_Descriptor := (others => <>);
            begin
               if Try_Map_Key_Value_Types (Unit, Document, Item.Type_Info, Key_Info, Value_Info) then
                  Add_From_Info (Synthetic_Optional_Type (Value_Info));
               else
                  Add_From_Info (Synthetic_Optional_Type (Element_Info));
               end if;
            end;
         end if;
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

   procedure Render_For_Of_Helper_Bodies
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Types    : GM.Type_Descriptor_Vectors.Vector;
      State    : in out Emit_State)
   is
      Generated_Helpers      : FT.UString_Vectors.Vector;
      Runtime_Dependency_Types : FT.UString_Vectors.Vector;
      procedure Render_Helper (Info : GM.Type_Descriptor);

      procedure Render_Helper (Info : GM.Type_Descriptor) is
         Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         Kind      : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Type_Key  : constant String := Render_Type_Name (Info);
         Type_Name : constant String := Render_Type_Name (Info);

         procedure Ensure_Helper (Name_Text : String) is
         begin
            if Name_Text'Length = 0 then
               return;
            end if;

            Render_Helper (Resolve_Type_Name (Unit, Document, Name_Text));
         end Ensure_Helper;
      begin
         if not Needs_Generated_Heap_Helper (Unit, Document, Info)
           or else Contains_Name (Generated_Helpers, Type_Key)
         then
            return;
         end if;

         if Kind = "array" and then Base.Has_Component_Type then
            Ensure_Helper (FT.To_String (Base.Component_Type));
         elsif Kind = "record" then
            for Field of Base.Fields loop
               Ensure_Helper (FT.To_String (Field.Type_Name));
            end loop;
            for Field of Base.Variant_Fields loop
               Ensure_Helper (FT.To_String (Field.Type_Name));
            end loop;
         elsif Is_Tuple_Type (Base) then
            for Item of Base.Tuple_Element_Types loop
               Ensure_Helper (FT.To_String (Item));
            end loop;
         end if;

         Generated_Helpers.Append (FT.To_UString (Type_Key));

         Append_Line
           (Buffer,
            "procedure "
            & For_Of_Copy_Helper_Name (Unit, Document, Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & For_Of_Copy_Helper_Name (Unit, Document, Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Copy_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_For_Of,
            "",
            Info,
            2);
         Append_Line (Buffer, "end " & For_Of_Copy_Helper_Name (Unit, Document, Info) & ";", 1);
         Append_Line (Buffer);

         Append_Line
           (Buffer,
            "function "
            & For_Of_Copy_Helper_Name (Unit, Document, Info)
            & " (Source : "
            & Type_Name
            & ") return "
            & Type_Name
            & ";",
            1);
         Append_Line
           (Buffer,
            "function "
            & For_Of_Copy_Helper_Name (Unit, Document, Info)
            & " (Source : "
            & Type_Name
            & ") return "
            & Type_Name
            & " is",
            1);
         Append_Line
           (Buffer,
            "Result : "
            & Type_Name
            & " := Source;",
            2);
         Append_Line (Buffer, "begin", 1);
         Append_Line
           (Buffer,
            For_Of_Copy_Helper_Name (Unit, Document, Info)
            & " (Result, Source);",
            2);
         Append_Line (Buffer, "return Result;", 2);
         Append_Line
           (Buffer,
            "end " & For_Of_Copy_Helper_Name (Unit, Document, Info) & ";",
            1);
         Append_Line (Buffer);

         Append_Local_Warning_Suppression (Buffer, 1);
         Append_Line
           (Buffer,
            "procedure "
            & For_Of_Free_Helper_Name (Unit, Document, Info)
            & " (Value : in out "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & For_Of_Free_Helper_Name (Unit, Document, Info)
            & " (Value : in out "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Free_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_For_Of,
            "",
            Info,
            2);
         Append_Line
           (Buffer,
            "Value := " & Default_Value_Expr (Unit, Document, Info) & ";",
            2);
         Append_Line (Buffer, "end " & For_Of_Free_Helper_Name (Unit, Document, Info) & ";", 1);
         Append_Local_Warning_Restore (Buffer, 1);
         Append_Line (Buffer);
      end Render_Helper;
   begin
      for Type_Item of Types loop
         Mark_Heap_Runtime_Dependencies
           (Unit,
            Document,
            Type_Item,
            State,
            Runtime_Dependency_Types);
         Render_Helper (Type_Item);
      end loop;
   end Render_For_Of_Helper_Bodies;

   procedure Render_Owner_Access_Helper_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor)
   is
      Type_Name   : constant String := Render_Type_Name (Type_Item);
      Target_Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Target));
      Result_Info : GM.Type_Descriptor := Type_Item;
      Runtime_Name : constant String := Local_Ownership_Runtime_Name (Type_Item);

      function Allocate_Post_Image return String is
         Result      : SU.Unbounded_String :=
           SU.To_Unbounded_String
             (Local_Allocate_Helper_Name (Type_Item) & "'Result /= null");
         Target_Info : constant GM.Type_Descriptor :=
           Resolve_Type_Name (Unit, Document, FT.To_String (Type_Item.Target));
      begin
         for Field of Target_Info.Fields loop
            declare
               Field_Name : constant String := FT.To_String (Field.Name);
               Field_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Field.Type_Name));
            begin
               if Owner_Allocate_Post_Field_Is_Trackable
                 (Unit, Document, Field_Info)
               then
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (ASCII.LF
                         & Indentation (2)
                         & "and then "
                         & Local_Allocate_Helper_Name (Type_Item)
                         & "'Result.all."
                         & Field_Name
                         & " = Value."
                         & Field_Name);
               end if;
            end;
         end loop;

         return SU.To_String (Result);
      end Allocate_Post_Image;
   begin
      if not Is_Owner_Access (Type_Item) or else not Type_Item.Has_Target then
         return;
      end if;

      Result_Info.Not_Null := True;

      Append_Line
        (Buffer,
         "package "
         & Runtime_Name
         & " is new Safe_Ownership_RT ("
         & ASCII.LF
         & Indentation (2)
         & "Target_Type => "
         & Target_Name
         & ","
         & ASCII.LF
         & Indentation (2)
         & "Access_Type => "
         & Type_Name
         & ");",
         1);
      Append_Line (Buffer);
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
         & Allocate_Post_Image
         & ";",
         1);
      Append_Line
        (Buffer,
         "procedure "
         & Local_Free_Helper_Name (Type_Item)
         & " (Value : in out "
         & Type_Name
         & ") renames "
         & Runtime_Name
         & ".Free;",
         1);
      Append_Line
        (Buffer,
         "procedure "
         & Local_Dispose_Helper_Name (Type_Item)
         & " (Value : in out "
         & Type_Name
         & ") renames "
         & Runtime_Name
         & ".Dispose;",
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
      pragma Unreferenced (State);
      Result_Info : GM.Type_Descriptor := Type_Item;
      Target_Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Target));
      Runtime_Name : constant String := Local_Ownership_Runtime_Name (Type_Item);
      Target_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Name (Unit, Document, FT.To_String (Type_Item.Target));
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
         & " is",
         1);
      Append_Line
        (Buffer,
         "Result : constant "
         & Render_Subtype_Indication (Unit, Document, Result_Info)
         & " := "
         & Runtime_Name
         & ".Allocate (Value);",
         2);
      Append_Line (Buffer, "begin", 1);
      for Field of Target_Info.Fields loop
         declare
            Field_Name : constant String := FT.To_String (Field.Name);
            Field_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name
                (Unit,
                 Document,
                 FT.To_String (Field.Type_Name));
         begin
            if Owner_Allocate_Post_Field_Is_Trackable
              (Unit, Document, Field_Info)
            then
               Append_Line
                 (Buffer,
                  "Result.all."
                  & Field_Name
                  & " := Value."
                  & Field_Name
                  & ";",
                  2);
            end if;
         end;
      end loop;
      Append_Line (Buffer, "return Result;", 2);
      Append_Line
        (Buffer,
         "end " & Local_Allocate_Helper_Name (Type_Item) & ";",
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
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Kind : constant String := FT.To_String (Type_Item.Kind);
   begin
      if Kind = "incomplete" then
         return "type " & Ada_Safe_Name (FT.To_String (Type_Item.Name)) & ";";
      elsif Kind = "integer" then
         return Render_Integer_Type_Decl (Type_Item);
      elsif Kind = "enum" then
         return Render_Enum_Type_Decl (Type_Item);
      elsif Kind = "binary" then
         return Render_Binary_Type_Decl (Type_Item);
      elsif Kind = "subtype" then
         return Render_Subtype_Type_Decl (Unit, Document, Type_Item);
      elsif Kind = "nominal" then
         return Render_Nominal_Type_Decl (Type_Item);
      elsif Kind = "array" then
         return Render_Array_Type_Decl (Unit, Document, Type_Item, State);
      elsif Kind = "tuple" then
         return Render_Tuple_Type_Decl (Unit, Document, Type_Item, State);
      elsif Is_Result_Builtin (Type_Item) then
         return Render_Result_Type_Decl (Type_Item, State);
      elsif Kind = "record" then
         return Render_Record_Type_Decl (Unit, Document, Type_Item, State);
      elsif Kind = "access" then
         return Render_Access_Type_Decl (Type_Item);
      elsif Kind = "float" then
         return Render_Float_Type_Decl (Type_Item);
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
         Identity_Runtime : constant Boolean :=
           Uses_Identity_Array_Runtime (Unit, Document, Type_Item);
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

         if not Identity_Runtime then
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
         end if;

         if not Identity_Runtime then
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
               Append_Line (Buffer, "pragma Unreferenced (Value);", 2);
               Append_Line (Buffer, "null;", 2);
            end if;
            Append_Line
              (Buffer,
               "end " & Array_Runtime_Free_Element_Name (Type_Item) & ";",
               1);
            Append_Line (Buffer);
         end if;
      end;
   end Render_Growable_Array_Helper_Body;

   function Sanitize_Type_Name_Component
     (Value : String) return String renames FNU.Sanitize_Type_Name_Component;

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

   function Preferred_Imported_Synthetic_Type
     (Unit : CM.Resolved_Unit;
      Info : GM.Type_Descriptor) return GM.Type_Descriptor
   is
      Name_Text : constant String := FT.To_String (Info.Name);
      Tail_Name : constant String := Synthetic_Type_Tail_Name (Name_Text);
      Kind_Text : constant String := FT.Lowercase (FT.To_String (Info.Kind));
      function Matches
        (Candidate : GM.Type_Descriptor) return Boolean is
         Candidate_Kind : constant String :=
           FT.Lowercase (FT.To_String (Candidate.Kind));
      begin
         return
           Synthetic_Type_Tail_Name (FT.To_String (Candidate.Name)) = Tail_Name
           and then
             (Kind_Text = ""
              or else Candidate_Kind = ""
              or else Candidate_Kind = Kind_Text);
      end Matches;
   begin
      if Tail_Name'Length < 2
        or else Tail_Name (Tail_Name'First .. Tail_Name'First + 1) /= "__"
      then
         return Info;
      end if;

      for Item of Unit.Imported_Types loop
         if Matches (Item) then
            return Item;
         end if;
      end loop;

      for Item of Unit.Imported_Subprograms loop
         if Item.Has_Return_Type and then Matches (Item.Return_Type) then
            return Item.Return_Type;
         end if;
         if not Item.Params.Is_Empty then
            for Param of Item.Params loop
               if Matches (Param.Type_Info) then
                  return Param.Type_Info;
               end if;
            end loop;
         end if;
      end loop;

      return Info;
   end Preferred_Imported_Synthetic_Type;

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

   function Type_Info_From_Name_Or_Synthetic
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Found_Synthetic : Boolean := False;
   begin
      if Type_Info_From_Name (Unit, Document, Name, Type_Info) then
         return True;
      end if;

      Type_Info := Synthetic_Bounded_String_Type (Name, Found_Synthetic);
      return Found_Synthetic;
   end Type_Info_From_Name_Or_Synthetic;

   function Local_Free_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Free_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Free_Helper_Name;

   function For_Of_Helper_Base_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
   begin
      return "For_Of_" & Sanitized_Helper_Name (Render_Type_Name (Info));
   end For_Of_Helper_Base_Name;

   procedure Mark_Heap_Runtime_Dependencies
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor;
      State     : in out Emit_State;
      Seen      : in out FT.UString_Vectors.Vector)
   is
      Base     : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Type_Key : constant String := Render_Type_Name (Info);

      procedure Add_From_Name (Name_Text : String) is
      begin
         if Name_Text'Length = 0 then
            return;
         end if;

         Mark_Heap_Runtime_Dependencies
           (Unit,
            Document,
            Resolve_Type_Name (Unit, Document, Name_Text),
            State,
            Seen);
      end Add_From_Name;
   begin
      if Contains_Name (Seen, Type_Key) then
         return;
      end if;

      Seen.Append (FT.To_UString (Type_Key));

      if Is_Plain_String_Type (Unit, Document, Base) then
         State.Needs_Safe_String_RT := True;
         return;
      elsif Is_Growable_Array_Type (Unit, Document, Base) then
         State.Needs_Safe_Array_RT := True;
         Add_From_Name (FT.To_String (Base.Component_Type));
         return;
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Has_Component_Type
      then
         Add_From_Name (FT.To_String (Base.Component_Type));
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "record" then
         for Field of Base.Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
         for Field of Base.Variant_Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
      elsif Is_Tuple_Type (Base) then
         for Item of Base.Tuple_Element_Types loop
            Add_From_Name (FT.To_String (Item));
         end loop;
      end if;
   end Mark_Heap_Runtime_Dependencies;

   procedure Append_Generated_Heap_Copy_Body
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Info        : GM.Type_Descriptor;
      Depth       : Natural)
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
   begin
      if Kind = "array" and then Base.Has_Component_Type then
         declare
            Component_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type));
         begin
            Append_Line (Buffer, "for Index in Source'Range loop", Depth);
            Append_Heap_Copy_Value
              (Buffer,
               Unit,
               Document,
               State,
               Family,
               Scope_Name,
               "Target (Index)",
               "Source (Index)",
               Component_Info,
               Depth + 1);
            Append_Line (Buffer, "end loop;", Depth);
         end;
      elsif Kind = "record" then
         if not Base.Variant_Fields.Is_Empty
           or else Has_Text (Base.Discriminant_Name)
           or else Has_Text (Base.Variant_Discriminant_Name)
         then
            Append_Line (Buffer, "Target := Source;", Depth);
            Append_Record_Heap_Copy_Assignments
              (Buffer,
               Unit,
               Document,
               State,
               Family,
               Scope_Name,
               Base,
               "Target.",
               "Source.",
               Depth);
         else
            for Field of Base.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
               begin
                  if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                     Append_Heap_Copy_Value
                       (Buffer,
                        Unit,
                        Document,
                        State,
                        Family,
                        Scope_Name,
                        "Target." & FT.To_String (Field.Name),
                        "Source." & FT.To_String (Field.Name),
                        Field_Info,
                        Depth);
                  else
                     Append_Line
                       (Buffer,
                        "Target."
                        & FT.To_String (Field.Name)
                        & " := Source."
                        & FT.To_String (Field.Name)
                        & ";",
                        Depth);
                  end if;
               end;
            end loop;
         end if;
      elsif Is_Tuple_Type (Base) then
         for Index in Base.Tuple_Element_Types.First_Index .. Base.Tuple_Element_Types.Last_Index loop
            declare
               Item_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Base.Tuple_Element_Types (Index)));
            begin
               if Has_Heap_Value_Type (Unit, Document, Item_Info) then
                  Append_Heap_Copy_Value
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Family,
                     Scope_Name,
                     "Target." & Tuple_Field_Name (Positive (Index)),
                     "Source." & Tuple_Field_Name (Positive (Index)),
                     Item_Info,
                     Depth);
               else
                  Append_Line
                    (Buffer,
                     "Target."
                     & Tuple_Field_Name (Positive (Index))
                     & " := Source."
                     & Tuple_Field_Name (Positive (Index))
                     & ";",
                     Depth);
               end if;
            end;
         end loop;
      end if;
   end Append_Generated_Heap_Copy_Body;

   procedure Append_Generated_Heap_Free_Body
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Info        : GM.Type_Descriptor;
      Depth       : Natural)
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
   begin
      if Kind = "array" and then Base.Has_Component_Type then
         declare
            Component_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type));
         begin
            if Has_Heap_Value_Type (Unit, Document, Component_Info) then
               Append_Line (Buffer, "for Index in Value'Range loop", Depth);
               Append_Heap_Free_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  Family,
                  Scope_Name,
                  "Value (Index)",
                  Component_Info,
                  Depth + 1);
               Append_Line (Buffer, "end loop;", Depth);
            end if;
         end;
      elsif Kind = "record" then
         Append_Record_Heap_Free_Statements
           (Buffer,
            Unit,
            Document,
            State,
            Family,
            Scope_Name,
            Base,
            "Value.",
            Depth);
      elsif Is_Tuple_Type (Base) then
         for Index in Base.Tuple_Element_Types.First_Index .. Base.Tuple_Element_Types.Last_Index loop
            declare
               Item_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Base.Tuple_Element_Types (Index)));
            begin
               if Has_Heap_Value_Type (Unit, Document, Item_Info) then
                  Append_Heap_Free_Value
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Family,
                     Scope_Name,
                     "Value." & Tuple_Field_Name (Positive (Index)),
                     Item_Info,
                     Depth);
               end if;
            end;
         end loop;
      end if;
   end Append_Generated_Heap_Free_Body;

   function Local_Allocate_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Allocate_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Allocate_Helper_Name;

   function Local_Dispose_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Dispose_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Dispose_Helper_Name;

   function Local_Ownership_Runtime_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Ownership_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Ownership_Runtime_Name;

   function Array_Runtime_Default_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_Default_Element";
   end Array_Runtime_Default_Element_Name;

   function Array_Runtime_Clone_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_Clone_Element";
   end Array_Runtime_Clone_Element_Name;

   function Uses_Identity_Array_Runtime
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Growable
        and then Base.Has_Component_Type
        and then
          not Has_Heap_Value_Type
            (Unit,
             Document,
             Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type)));
   end Uses_Identity_Array_Runtime;

   function Tuple_Field_Name (Index : Positive) return String is
   begin
      return "F" & Ada.Strings.Fixed.Trim (Positive'Image (Index), Ada.Strings.Both);
   end Tuple_Field_Name;

   function Render_Scalar_Value (Value : GM.Scalar_Value) return String is
   begin
      case Value.Kind is
         when GM.Scalar_Value_Integer =>
            return Trim_Image (Value.Int_Value);
         when GM.Scalar_Value_Boolean =>
            return (if Value.Bool_Value then "true" else "false");
         when GM.Scalar_Value_Character =>
            return FT.To_String (Value.Text);
         when GM.Scalar_Value_Enum =>
            return
              Render_Enum_Literal_Name
                (FT.To_String (Value.Text), FT.To_String (Value.Type_Name));
         when others =>
            return "";
      end case;
   end Render_Scalar_Value;

   function Render_Integer_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
      return
        "type "
        & Name
        & " is range "
        & Trim_Image (Type_Item.Low)
        & " .. "
        & Trim_Image (Type_Item.High)
        & ";";
   end Render_Integer_Type_Decl;

   function Render_Enum_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Result : SU.Unbounded_String :=
        SU.To_Unbounded_String ("type " & Ada_Safe_Name (FT.To_String (Type_Item.Name)) & " is (");
   begin
      for Index in Type_Item.Enum_Literals.First_Index .. Type_Item.Enum_Literals.Last_Index loop
         if Index /= Type_Item.Enum_Literals.First_Index then
            Result := Result & SU.To_Unbounded_String (", ");
         end if;
         Result :=
           Result
           & SU.To_Unbounded_String
               (Ada_Safe_Name (FT.To_String (Type_Item.Enum_Literals (Index))));
      end loop;
      Result := Result & SU.To_Unbounded_String (");");
      return SU.To_String (Result);
   end Render_Enum_Type_Decl;

   function Render_Binary_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
      return
        "type "
        & Name
        & " is mod 2 ** "
        & Ada.Strings.Fixed.Trim (Positive'Image (Type_Item.Bit_Width), Ada.Strings.Both)
        & ";";
   end Render_Binary_Type_Decl;

   function Render_Subtype_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor) return String
   is
      pragma Unreferenced (Unit, Document);
      Name   : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Result : SU.Unbounded_String;
   begin
      if not Type_Item.Discriminant_Constraints.Is_Empty then
         Result :=
           SU.To_Unbounded_String
             ("subtype "
              & Name
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
           & Name
           & " is "
           & Ada_Safe_Name (FT.To_String (Type_Item.Base))
           & " range "
           & Trim_Image (Type_Item.Low)
           & " .. "
           & Trim_Image (Type_Item.High)
           & ";";
      end if;

      return
        "subtype "
        & Name
        & " is "
        & Ada_Safe_Name (FT.To_String (Type_Item.Base))
        & ";";
   end Render_Subtype_Type_Decl;

   function Render_Nominal_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Base : constant String := Ada_Qualified_Name (FT.To_String (Type_Item.Base));
   begin
      if Type_Item.Has_Low and then Type_Item.Has_High then
         return
           "type "
           & Name
           & " is new "
           & Base
           & " range "
           & Trim_Image (Type_Item.Low)
           & " .. "
           & Trim_Image (Type_Item.High)
           & ";";
      end if;

      return
        "type "
        & Name
        & " is new "
        & Base
        & ";";
   end Render_Nominal_Type_Decl;

   function Render_Array_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
      if Type_Item.Growable or else Type_Item.Index_Types.Is_Empty then
         declare
            Identity_Runtime : constant Boolean :=
              Uses_Identity_Array_Runtime (Unit, Document, Type_Item);
            Runtime_Generic_Name : constant String :=
              Array_Runtime_Generic_Name (Unit, Document, Type_Item);
            Component_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name
                (Unit,
                 Document,
                 FT.To_String (Type_Item.Component_Type));
            Element_Type_Name : constant String :=
              Render_Type_Name_From_Text
                (Unit,
                 Document,
                 FT.To_String (Type_Item.Component_Type),
                 State);
            Default_Image : constant String :=
              Default_Value_Expr (Unit, Document, Component_Info);
            Clone_Post : constant String :=
              (if Identity_Runtime
               then
                 ASCII.LF
                 & Indentation (3)
                 & "Post => "
                 & Array_Runtime_Clone_Element_Name (Type_Item)
                 & "'Result = Source;"
               else
                 ";");
         begin
            if Runtime_Generic_Name = "Safe_Array_RT" then
               State.Needs_Safe_Array_RT := True;
            end if;
            return
              "function "
              & Array_Runtime_Default_Element_Name (Type_Item)
              & " return "
              & Element_Type_Name
              & (if Identity_Runtime then " is (" & Default_Image & ")" else "")
              & ASCII.LF
              & Indentation (2)
              & "with Global => null;"
              & ASCII.LF
              & Indentation (1)
              & "function "
              & Array_Runtime_Clone_Element_Name (Type_Item)
              & " (Source : "
              & Element_Type_Name
              & ") return "
              & Element_Type_Name
              & (if Identity_Runtime then " is (Source)" else "")
              & ASCII.LF
              & Indentation (2)
              & "with Global => null"
              & (if Identity_Runtime then "," & Clone_Post else ";")
              & ASCII.LF
              & Indentation (1)
              & "procedure "
              & Array_Runtime_Free_Element_Name (Type_Item)
              & " (Value : in out "
              & Element_Type_Name
              & ")"
              & (if Identity_Runtime
                 then
                   " is null;"
                 else
                   ASCII.LF
                   & Indentation (2)
                   & "with Global => null,"
                   & ASCII.LF
                   & Indentation (3)
                   & "Always_Terminates;")
              & ASCII.LF
              & (if Identity_Runtime
                 then
                   Indentation (1)
                   & "package "
                   & Array_Runtime_Identity_Ops_Name (Type_Item)
                   & " is new Safe_Array_Identity_Ops"
                   & ASCII.LF
                   & Indentation (2)
                   & "(Element_Type => "
                   & Element_Type_Name
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
                 else
                   "")
              & Indentation (1)
              & "package "
              & Array_Runtime_Instance_Name (Type_Item)
              & " is new "
              & Runtime_Generic_Name
              & ASCII.LF
              & Indentation (2)
              & (if Identity_Runtime
                 then
                   "(Element_Ops => "
                   & Array_Runtime_Identity_Ops_Name (Type_Item)
                   & ");"
                 else
                   "(Element_Type => "
                   & Element_Type_Name
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
                   & ");")
              & ASCII.LF
              & Indentation (1)
              & "subtype "
              & Name
              & " is "
              & Array_Runtime_Instance_Name (Type_Item)
              & ".Safe_Array;";
         end;
      end if;

      return
        "type "
        & Name
        & " is array ("
        & Join_Names (Type_Item.Index_Types)
        & ") of "
        & Render_Type_Name_From_Text
            (Unit,
             Document,
             FT.To_String (Type_Item.Component_Type),
             State)
        & ";";
   end Render_Array_Type_Decl;

   function Render_Tuple_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Result : SU.Unbounded_String :=
        SU.To_Unbounded_String ("type " & Ada_Safe_Name (FT.To_String (Type_Item.Name)));
   begin
      Result := Result & SU.To_Unbounded_String (" is record" & ASCII.LF);
      for Index in Type_Item.Tuple_Element_Types.First_Index .. Type_Item.Tuple_Element_Types.Last_Index loop
         Result :=
           Result
           & SU.To_Unbounded_String
               (Indentation (1)
                & Tuple_Field_Name (Positive (Index))
                & " : "
                & Render_Type_Name_From_Text
                    (Unit,
                     Document,
                     FT.To_String (Type_Item.Tuple_Element_Types (Index)),
                     State)
                & ";"
                & ASCII.LF);
      end loop;
      Result := Result & SU.To_Unbounded_String ("end record;");
      return SU.To_String (Result);
   end Render_Tuple_Type_Decl;

   function Render_Result_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
   begin
      State.Needs_Ada_Strings_Unbounded := True;
      return
        "type "
        & Ada_Safe_Name (FT.To_String (Type_Item.Name))
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
   end Render_Result_Type_Decl;

   function Render_Record_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Name   : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Result : SU.Unbounded_String;

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

      function Has_Others_Choice return Boolean is
      begin
         for Field of Type_Item.Variant_Fields loop
            if Field.Is_Others then
               return True;
            end if;
         end loop;
         return False;
      end Has_Others_Choice;

      function Needs_Null_Others_Branch return Boolean is
         Disc_Type : constant String :=
           FT.Lowercase (FT.To_String (Type_Item.Discriminant_Type));
         Has_True  : Boolean := False;
         Has_False : Boolean := False;
      begin
         if Has_Others_Choice or else Disc_Type /= "boolean" then
            return False;
         end if;

         for Field of Type_Item.Variant_Fields loop
            if Field.Choice.Kind = GM.Scalar_Value_Boolean then
               if Field.Choice.Bool_Value then
                  Has_True := True;
               else
                  Has_False := True;
               end if;
            end if;
         end loop;
         return not (Has_True and Has_False);
      end Needs_Null_Others_Branch;

      procedure Append_Missing_Enum_Null_Branches is
         Disc_Type_Info : GM.Type_Descriptor := (others => <>);
         Has_Disc_Type  : constant Boolean :=
           Has_Text (Type_Item.Discriminant_Type)
           and then Has_Type (Unit, Document, FT.To_String (Type_Item.Discriminant_Type));

         function Has_Explicit_Choice (Choice_Name : String) return Boolean is
         begin
            for Field of Type_Item.Variant_Fields loop
               if not Field.Is_Others
                 and then Render_Scalar_Value (Field.Choice) = Choice_Name
               then
                  return True;
               end if;
            end loop;
            return False;
         end Has_Explicit_Choice;
      begin
         if Has_Others_Choice or else not Has_Disc_Type then
            return;
         end if;

         Disc_Type_Info :=
           Lookup_Type (Unit, Document, FT.To_String (Type_Item.Discriminant_Type));
         if FT.To_String (Disc_Type_Info.Kind) /= "enum" then
            return;
         end if;

         for Literal of Disc_Type_Info.Enum_Literals loop
            declare
               Choice_Name : constant String :=
                 Ada_Safe_Name (FT.To_String (Literal));
            begin
               if not Has_Explicit_Choice (Choice_Name) then
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (Indentation (1)
                         & "when "
                         & Choice_Name
                         & " =>"
                         & ASCII.LF
                         & Indentation (2)
                         & "null;"
                         & ASCII.LF);
               end if;
            end;
         end loop;
      end Append_Missing_Enum_Null_Branches;

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
         Result := Result & SU.To_Unbounded_String (" (");
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
                     (Ada_Safe_Name (FT.To_String (Disc.Name))
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
                & Ada_Safe_Name (FT.To_String (Type_Item.Discriminant_Name))
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
              (Ada_Safe_Name (FT.To_String (Field.Name)),
               Render_Type_Name_From_Text
                 (Unit,
                  Document,
                  FT.To_String (Field.Type_Name),
                  State),
               1);
         end if;
      end loop;
      if not Type_Item.Variant_Fields.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               (Indentation (1)
                & "case "
                & Ada_Safe_Name
                    (FT.To_String
                       ((if Has_Text (Type_Item.Variant_Discriminant_Name)
                         then Type_Item.Variant_Discriminant_Name
                         else Type_Item.Discriminant_Name)))
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
                       (Ada_Safe_Name (FT.To_String (Type_Item.Variant_Fields (Index).Name)),
                        Render_Type_Name_From_Text
                          (Unit,
                           Document,
                           FT.To_String (Type_Item.Variant_Fields (Index).Type_Name),
                           State),
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
         if Needs_Null_Others_Branch then
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Indentation (1)
                   & "when others =>"
                   & ASCII.LF
                   & Indentation (2)
                   & "null;"
                   & ASCII.LF);
         end if;
         Append_Missing_Enum_Null_Branches;
         Result :=
           Result
           & SU.To_Unbounded_String
               (Indentation (1) & "end case;" & ASCII.LF);
      end if;
      Result := Result & SU.To_Unbounded_String ("end record;");
      return SU.To_String (Result);
   end Render_Record_Type_Decl;

   function Render_Access_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
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
   end Render_Access_Type_Decl;

   function Render_Float_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
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
   end Render_Float_Type_Decl;

   function Synthetic_Type_Tail_Name (Name : String) return String is
      Dot_Index : Natural := 0;
   begin
      for Index in reverse Name'Range loop
         if Name (Index) = '.' then
            Dot_Index := Index;
            exit;
         end if;
      end loop;
      if Dot_Index = 0 then
         return Name;
      end if;
      return Name (Dot_Index + 1 .. Name'Last);
   end Synthetic_Type_Tail_Name;

   procedure Append_Record_Heap_Copy_Assignments
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Target_Prefix : String;
      Source_Prefix : String;
      Depth       : Natural)
   is
   begin
      for Field of Base.Fields loop
         declare
            Field_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
         begin
            if Has_Heap_Value_Type (Unit, Document, Field_Info) then
               Append_Heap_Copy_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  Family,
                  Scope_Name,
                  Target_Prefix & FT.To_String (Field.Name),
                  Source_Prefix & FT.To_String (Field.Name),
                  Field_Info,
                  Depth);
            end if;
         end;
      end loop;

      if not Base.Variant_Fields.Is_Empty then
         declare
            Disc_Name : constant String :=
              FT.To_String
                ((if Has_Text (Base.Variant_Discriminant_Name)
                  then Base.Variant_Discriminant_Name
                  else Base.Discriminant_Name));
            Index : Positive := Base.Variant_Fields.First_Index;
         begin
            if Disc_Name'Length = 0 then
               return;
            end if;

            Append_Line (Buffer, "case " & Source_Prefix & Disc_Name & " is", Depth);
            while Index <= Base.Variant_Fields.Last_Index loop
               declare
                  First_Field : constant GM.Variant_Field :=
                    Base.Variant_Fields (Index);
                  Emitted_Statements : Boolean := False;
               begin
                  Append_Line
                    (Buffer,
                     "when "
                     & (if First_Field.Is_Others
                        then "others"
                        else Render_Scalar_Value (First_Field.Choice))
                     & " =>",
                     Depth + 1);
                  loop
                     declare
                        Variant_Field : constant GM.Variant_Field :=
                          Base.Variant_Fields (Index);
                        Field_Info : constant GM.Type_Descriptor :=
                          Resolve_Type_Name
                            (Unit,
                             Document,
                             FT.To_String (Variant_Field.Type_Name));
                     begin
                        if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                           Append_Heap_Copy_Value
                             (Buffer,
                              Unit,
                              Document,
                              State,
                              Family,
                              Scope_Name,
                              Target_Prefix & FT.To_String (Variant_Field.Name),
                              Source_Prefix & FT.To_String (Variant_Field.Name),
                              Field_Info,
                              Depth + 2);
                           Emitted_Statements := True;
                        end if;
                     end;
                     exit when Index = Base.Variant_Fields.Last_Index;
                     exit when not Same_Variant_Choice
                       (First_Field,
                        Base.Variant_Fields (Index + 1));
                     Index := Index + 1;
                  end loop;
                  if not Emitted_Statements then
                     Append_Line (Buffer, "null;", Depth + 2);
                  end if;
                  Index := Index + 1;
               end;
            end loop;
            Append_Line (Buffer, "end case;", Depth);
         end;
      end if;
   end Append_Record_Heap_Copy_Assignments;

   procedure Append_Record_Heap_Free_Statements
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Value_Prefix : String;
      Depth       : Natural)
   is
   begin
      for Field of Base.Fields loop
         declare
            Field_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
         begin
            if Has_Heap_Value_Type (Unit, Document, Field_Info) then
               Append_Heap_Free_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  Family,
                  Scope_Name,
                  Value_Prefix & FT.To_String (Field.Name),
                  Field_Info,
                  Depth);
            end if;
         end;
      end loop;

      if not Base.Variant_Fields.Is_Empty then
         declare
            Disc_Name : constant String :=
              FT.To_String
                ((if Has_Text (Base.Variant_Discriminant_Name)
                  then Base.Variant_Discriminant_Name
                  else Base.Discriminant_Name));
            Index : Positive := Base.Variant_Fields.First_Index;
         begin
            if Disc_Name'Length = 0 then
               return;
            end if;

            Append_Line (Buffer, "case " & Value_Prefix & Disc_Name & " is", Depth);
            while Index <= Base.Variant_Fields.Last_Index loop
               declare
                  First_Field : constant GM.Variant_Field :=
                    Base.Variant_Fields (Index);
                  Emitted_Statements : Boolean := False;
               begin
                  Append_Line
                    (Buffer,
                     "when "
                     & (if First_Field.Is_Others
                        then "others"
                        else Render_Scalar_Value (First_Field.Choice))
                     & " =>",
                     Depth + 1);
                  loop
                     declare
                        Variant_Field : constant GM.Variant_Field :=
                          Base.Variant_Fields (Index);
                        Field_Info : constant GM.Type_Descriptor :=
                          Resolve_Type_Name
                            (Unit,
                             Document,
                             FT.To_String (Variant_Field.Type_Name));
                     begin
                        if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                           Append_Heap_Free_Value
                             (Buffer,
                              Unit,
                              Document,
                              State,
                              Family,
                              Scope_Name,
                              Value_Prefix & FT.To_String (Variant_Field.Name),
                              Field_Info,
                              Depth + 2);
                           Emitted_Statements := True;
                        end if;
                     end;
                     exit when Index = Base.Variant_Fields.Last_Index;
                     exit when not Same_Variant_Choice
                       (First_Field,
                        Base.Variant_Fields (Index + 1));
                     Index := Index + 1;
                  end loop;
                  if not Emitted_Statements then
                     Append_Line (Buffer, "null;", Depth + 2);
                  end if;
                  Index := Index + 1;
               end;
            end loop;
            Append_Line (Buffer, "end case;", Depth);
         end;
      end if;
   end Append_Record_Heap_Free_Statements;

   function Array_Runtime_Generic_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
   begin
      if Uses_Identity_Array_Runtime (Unit, Document, Info) then
         return "Safe_Array_Identity_RT";
      end if;
      return "Safe_Array_RT";
   end Array_Runtime_Generic_Name;

   function Array_Runtime_Identity_Ops_Name
     (Info : GM.Type_Descriptor) return String is
   begin
      return Array_Runtime_Instance_Name (Info) & "_Element_Ops";
   end Array_Runtime_Identity_Ops_Name;

   function Same_Variant_Choice
     (Left, Right : GM.Variant_Field) return Boolean is
   begin
      return Left.Is_Others = Right.Is_Others
        and then
          (if Left.Is_Others
           then True
           else Left.Choice.Kind = Right.Choice.Kind
             and then Render_Scalar_Value (Left.Choice) = Render_Scalar_Value (Right.Choice));
   end Same_Variant_Choice;

end Safe_Frontend.Ada_Emit.Types;
