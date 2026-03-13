with Ada.Containers;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Hash;
with GNATCOLL.JSON;

package body Safe_Frontend.Interfaces is
   package String_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Loaded_Interface,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => "=");

   package Span_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => FT.Source_Span,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => FT."=");

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   use type Ada.Containers.Count_Type;

   function Canonical (Name : String) return String is
   begin
      return FT.Lowercase (Name);
   end Canonical;

   function Json_Array_Or_Empty
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Array;

   function Field_Or_Null
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Value;

   function Parse_Span
     (Value : GNATCOLL.JSON.JSON_Value) return FT.Source_Span;

   function Parse_Type
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Type_Descriptor;

   function Require_Type_Value
     (Value     : GNATCOLL.JSON.JSON_Value;
      Context   : String;
      File_Path : String) return GM.Type_Descriptor;

   function Require_Type_Field
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      Context      : String;
      File_Path    : String) return GM.Type_Descriptor;

   function Require_String
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return String;

   function Require_Positive_Int
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return Long_Long_Integer;

   function Require_Boolean
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return Boolean;

   function Require_Array
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return GNATCOLL.JSON.JSON_Array;

   procedure Validate_Name_List
     (Value     : GNATCOLL.JSON.JSON_Array;
      Field     : String;
      File_Path : String);

   procedure Validate_Decl_List
     (Value     : GNATCOLL.JSON.JSON_Array;
      Field     : String;
      File_Path : String);

   procedure Validate_Effect_Summaries
     (Value     : GNATCOLL.JSON.JSON_Array;
      File_Path : String);

   procedure Validate_Channel_Summaries
     (Value     : GNATCOLL.JSON.JSON_Array;
      File_Path : String);

   function Discover_Interface_Files (Dir : String) return String_Vectors.Vector;

   function Parse_Interface_File
     (File_Path : String;
      Unit_Path : String) return Loaded_Interface;

   function Json_Array_Or_Empty
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Array
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind = JSON_Object_Type
        and then Has_Field (Object_Value, Field)
        and then Get (Object_Value, Field).Kind = JSON_Array_Type
      then
         return Get (Object_Value, Field);
      end if;
      return Empty_Array;
   end Json_Array_Or_Empty;

   function Field_Or_Null
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Value
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind = JSON_Object_Type and then Has_Field (Object_Value, Field) then
         return Get (Object_Value, Field);
      end if;
      return Create;
   end Field_Or_Null;

   function Parse_Span
     (Value : GNATCOLL.JSON.JSON_Value) return FT.Source_Span
   is
      use GNATCOLL.JSON;
      Result : FT.Source_Span := FT.Null_Span;
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "start_line")
        and then Get (Value, "start_line").Kind = JSON_Int_Type
      then
         Result.Start_Pos.Line :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "start_line"))));
      end if;
      if Has_Field (Value, "start_col")
        and then Get (Value, "start_col").Kind = JSON_Int_Type
      then
         Result.Start_Pos.Column :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "start_col"))));
      end if;
      if Has_Field (Value, "end_line")
        and then Get (Value, "end_line").Kind = JSON_Int_Type
      then
         Result.End_Pos.Line :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "end_line"))));
      else
         Result.End_Pos.Line := Result.Start_Pos.Line;
      end if;
      if Has_Field (Value, "end_col")
        and then Get (Value, "end_col").Kind = JSON_Int_Type
      then
         Result.End_Pos.Column :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "end_col"))));
      else
         Result.End_Pos.Column := Result.Start_Pos.Column;
      end if;
      return Result;
   end Parse_Span;

   function Parse_Type
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Type_Descriptor
   is
      use GNATCOLL.JSON;
      Result : GM.Type_Descriptor;

      procedure Append_Field (Name : UTF8_String; Field_Value : JSON_Value) is
         Field_Entry : GM.Type_Field;
      begin
         Field_Entry.Name := FT.To_UString (Name);
         if Field_Value.Kind = JSON_String_Type then
            Field_Entry.Type_Name := FT.To_UString (Get (Field_Value));
         end if;
         Result.Fields.Append (Field_Entry);
      end Append_Field;
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "name") and then Get (Value, "name").Kind = JSON_String_Type then
         Result.Name := FT.To_UString (Get (Value, "name"));
      end if;
      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Result.Kind := FT.To_UString (Get (Value, "kind"));
      end if;
      if Has_Field (Value, "low") and then Get (Value, "low").Kind = JSON_Int_Type then
         Result.Has_Low := True;
         Result.Low := Get (Get (Value, "low"));
      end if;
      if Has_Field (Value, "high") and then Get (Value, "high").Kind = JSON_Int_Type then
         Result.Has_High := True;
         Result.High := Get (Get (Value, "high"));
      end if;
      if Has_Field (Value, "base") and then Get (Value, "base").Kind = JSON_String_Type then
         Result.Has_Base := True;
         Result.Base := FT.To_UString (Get (Value, "base"));
      end if;
      if Has_Field (Value, "digits_text")
        and then Get (Value, "digits_text").Kind = JSON_String_Type
      then
         Result.Has_Digits_Text := True;
         Result.Digits_Text := FT.To_UString (Get (Value, "digits_text"));
      end if;
      if Has_Field (Value, "float_low_text")
        and then Get (Value, "float_low_text").Kind = JSON_String_Type
      then
         Result.Has_Float_Low_Text := True;
         Result.Float_Low_Text := FT.To_UString (Get (Value, "float_low_text"));
      end if;
      if Has_Field (Value, "float_high_text")
        and then Get (Value, "float_high_text").Kind = JSON_String_Type
      then
         Result.Has_Float_High_Text := True;
         Result.Float_High_Text := FT.To_UString (Get (Value, "float_high_text"));
      end if;
      if Has_Field (Value, "component_type")
        and then Get (Value, "component_type").Kind = JSON_String_Type
      then
         Result.Has_Component_Type := True;
         Result.Component_Type := FT.To_UString (Get (Value, "component_type"));
      end if;
      if Has_Field (Value, "target")
        and then Get (Value, "target").Kind = JSON_String_Type
      then
         Result.Has_Target := True;
         Result.Target := FT.To_UString (Get (Value, "target"));
      end if;
      if Has_Field (Value, "discriminant_name")
        and then Get (Value, "discriminant_name").Kind = JSON_String_Type
      then
         Result.Has_Discriminant := True;
         Result.Discriminant_Name := FT.To_UString (Get (Value, "discriminant_name"));
      end if;
      if Has_Field (Value, "discriminant_type")
        and then Get (Value, "discriminant_type").Kind = JSON_String_Type
      then
         Result.Has_Discriminant := True;
         Result.Discriminant_Type := FT.To_UString (Get (Value, "discriminant_type"));
      end if;
      if Has_Field (Value, "discriminant_default")
        and then Get (Value, "discriminant_default").Kind = JSON_Boolean_Type
      then
         Result.Has_Discriminant_Default := True;
         Result.Discriminant_Default_Bool := Get (Get (Value, "discriminant_default"));
      end if;
      if Has_Field (Value, "access_role")
        and then Get (Value, "access_role").Kind = JSON_String_Type
      then
         Result.Has_Access_Role := True;
         Result.Access_Role := FT.To_UString (Get (Value, "access_role"));
      end if;
      if Has_Field (Value, "unconstrained")
        and then Get (Value, "unconstrained").Kind = JSON_Boolean_Type
      then
         Result.Unconstrained := Get (Get (Value, "unconstrained"));
      end if;
      if Has_Field (Value, "not_null")
        and then Get (Value, "not_null").Kind = JSON_Boolean_Type
      then
         Result.Not_Null := Get (Get (Value, "not_null"));
      end if;
      if Has_Field (Value, "anonymous")
        and then Get (Value, "anonymous").Kind = JSON_Boolean_Type
      then
         Result.Anonymous := Get (Get (Value, "anonymous"));
      end if;
      if Has_Field (Value, "is_constant")
        and then Get (Value, "is_constant").Kind = JSON_Boolean_Type
      then
         Result.Is_Constant := Get (Get (Value, "is_constant"));
      end if;
      if Has_Field (Value, "is_all")
        and then Get (Value, "is_all").Kind = JSON_Boolean_Type
      then
         Result.Is_All := Get (Get (Value, "is_all"));
      end if;

      declare
         Index_Types : constant JSON_Array := Json_Array_Or_Empty (Value, "index_types");
      begin
         for Index in 1 .. Length (Index_Types) loop
            declare
               Item : constant JSON_Value := Get (Index_Types, Index);
            begin
               if Item.Kind = JSON_String_Type then
                  Result.Index_Types.Append (FT.To_UString (Get (Item)));
               end if;
            end;
         end loop;
      end;

      if Has_Field (Value, "fields")
        and then Get (Value, "fields").Kind = JSON_Object_Type
      then
         Map_JSON_Object (Get (Value, "fields"), Append_Field'Access);
      end if;

      declare
         Variants : constant JSON_Array := Json_Array_Or_Empty (Value, "variant_fields");
      begin
         for Index in 1 .. Length (Variants) loop
            declare
               Item : constant JSON_Value := Get (Variants, Index);
               Variant_Field : GM.Variant_Field;
            begin
               if Item.Kind = JSON_Object_Type then
                  if Has_Field (Item, "name")
                    and then Get (Item, "name").Kind = JSON_String_Type
                  then
                     Variant_Field.Name := FT.To_UString (Get (Item, "name"));
                  end if;
                  if Has_Field (Item, "type")
                    and then Get (Item, "type").Kind = JSON_String_Type
                  then
                     Variant_Field.Type_Name := FT.To_UString (Get (Item, "type"));
                  end if;
                  if Has_Field (Item, "when")
                    and then Get (Item, "when").Kind = JSON_Boolean_Type
                  then
                     Variant_Field.When_True := Get (Get (Item, "when"));
                  end if;
                  Result.Variant_Fields.Append (Variant_Field);
               end if;
            end;
         end loop;
      end;

      return Result;
   end Parse_Type;

   function Require_Type_Value
     (Value     : GNATCOLL.JSON.JSON_Value;
      Context   : String;
      File_Path : String) return GM.Type_Descriptor
   is
      use GNATCOLL.JSON;
      Result : constant GM.Type_Descriptor := Parse_Type (Value);
   begin
      if Value.Kind /= JSON_Object_Type then
         raise Constraint_Error with File_Path & ": " & Context & " must be an object";
      end if;

      if FT.To_String (Result.Name) = "" or else FT.To_String (Result.Kind) = "" then
         raise Constraint_Error with
           File_Path & ": " & Context & " must include non-empty type name and kind";
      end if;

      return Result;
   end Require_Type_Value;

   function Require_Type_Field
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      Context      : String;
      File_Path    : String) return GM.Type_Descriptor
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind /= JSON_Object_Type or else not Has_Field (Object_Value, Field) then
         raise Constraint_Error with File_Path & ": missing required field `" & Field & "`";
      end if;

      return Require_Type_Value (Get (Object_Value, Field), Context, File_Path);
   end Require_Type_Field;

   function Require_String
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return String
   is
      use GNATCOLL.JSON;
      Value : JSON_Value;
   begin
      if Object_Value.Kind /= JSON_Object_Type
        or else not Has_Field (Object_Value, Field)
      then
         raise Constraint_Error with File_Path & ": field `" & Field & "` must be a non-empty string";
      end if;
      Value := Get (Object_Value, Field);
      if Value.Kind /= JSON_String_Type or else Get (Value) = "" then
         raise Constraint_Error with File_Path & ": field `" & Field & "` must be a non-empty string";
      end if;
      return Get (Value);
   end Require_String;

   function Require_Positive_Int
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return Long_Long_Integer
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind /= JSON_Object_Type
        or else not Has_Field (Object_Value, Field)
        or else Get (Object_Value, Field).Kind /= JSON_Int_Type
      then
         raise Constraint_Error with File_Path & ": field `" & Field & "` must be an integer";
      end if;

      declare
         Value : constant Long_Long_Integer := Get (Get (Object_Value, Field));
      begin
         if Value <= 0 then
            raise Constraint_Error with File_Path & ": field `" & Field & "` must be positive";
         end if;
         return Value;
      end;
   end Require_Positive_Int;

   function Require_Boolean
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return Boolean
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind /= JSON_Object_Type
        or else not Has_Field (Object_Value, Field)
        or else Get (Object_Value, Field).Kind /= JSON_Boolean_Type
      then
         raise Constraint_Error with File_Path & ": field `" & Field & "` must be a boolean";
      end if;
      return Get (Get (Object_Value, Field));
   end Require_Boolean;

   function Require_Array
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      File_Path    : String) return GNATCOLL.JSON.JSON_Array
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind /= JSON_Object_Type
        or else not Has_Field (Object_Value, Field)
        or else Get (Object_Value, Field).Kind /= JSON_Array_Type
      then
         raise Constraint_Error with File_Path & ": field `" & Field & "` must be an array";
      end if;
      return Get (Object_Value, Field);
   end Require_Array;

   procedure Validate_Name_List
     (Value     : GNATCOLL.JSON.JSON_Array;
      Field     : String;
      File_Path : String)
   is
      use GNATCOLL.JSON;
   begin
      for Index in 1 .. Length (Value) loop
         declare
            Item : constant JSON_Value := Get (Value, Index);
         begin
            if Item.Kind /= JSON_String_Type or else Get (Item) = "" then
               raise Constraint_Error with File_Path & ": " & Field & " must contain non-empty strings";
            end if;
         end;
      end loop;
   end Validate_Name_List;

   procedure Validate_Decl_List
     (Value     : GNATCOLL.JSON.JSON_Array;
      Field     : String;
      File_Path : String)
   is
      use GNATCOLL.JSON;
   begin
      for Index in 1 .. Length (Value) loop
         declare
            Item            : constant JSON_Value := Get (Value, Index);
            Ignore_Name      : constant String := Require_String (Item, "name", File_Path);
            Ignore_Kind      : constant String := Require_String (Item, "kind", File_Path);
            Ignore_Signature : constant String := Require_String (Item, "signature", File_Path);
            Ignore_Span      : constant FT.Source_Span := Parse_Span (Field_Or_Null (Item, "span"));
         begin
            null;
         end;
      end loop;
      pragma Unreferenced (Field);
   end Validate_Decl_List;

   procedure Validate_Effect_Summaries
     (Value     : GNATCOLL.JSON.JSON_Array;
      File_Path : String)
   is
      use GNATCOLL.JSON;
   begin
      for Index in 1 .. Length (Value) loop
         declare
            Item             : constant JSON_Value := Get (Value, Index);
            Depends          : constant JSON_Array := Require_Array (Item, "depends", File_Path);
            Ignore_Name      : constant String := Require_String (Item, "name", File_Path);
            Ignore_Signature : constant String := Require_String (Item, "signature", File_Path);
         begin
            Validate_Name_List (Require_Array (Item, "reads", File_Path), "reads", File_Path);
            Validate_Name_List (Require_Array (Item, "writes", File_Path), "writes", File_Path);
            Validate_Name_List (Require_Array (Item, "inputs", File_Path), "inputs", File_Path);
            Validate_Name_List (Require_Array (Item, "outputs", File_Path), "outputs", File_Path);
            for Dep_Index in 1 .. Length (Depends) loop
               declare
                  Dep_Item          : constant JSON_Value := Get (Depends, Dep_Index);
                  Ignore_Output_Name : constant String :=
                    Require_String (Dep_Item, "output_name", File_Path);
               begin
                  Validate_Name_List (Require_Array (Dep_Item, "inputs", File_Path), "depends.inputs", File_Path);
                  null;
               end;
            end loop;
            null;
         end;
      end loop;
   end Validate_Effect_Summaries;

   procedure Validate_Channel_Summaries
     (Value     : GNATCOLL.JSON.JSON_Array;
      File_Path : String)
   is
      use GNATCOLL.JSON;
   begin
      for Index in 1 .. Length (Value) loop
         declare
            Item             : constant JSON_Value := Get (Value, Index);
            Ignore_Name      : constant String := Require_String (Item, "name", File_Path);
            Ignore_Signature : constant String := Require_String (Item, "signature", File_Path);
         begin
            Validate_Name_List (Require_Array (Item, "channels", File_Path), "channels", File_Path);
            null;
         end;
      end loop;
   end Validate_Channel_Summaries;

   function Discover_Interface_Files (Dir : String) return String_Vectors.Vector is
      use Ada.Directories;
      Result : String_Vectors.Vector;
      Search : Search_Type;
      Dir_Entry  : Directory_Entry_Type;
   begin
      if not Exists (Dir) or else Kind (Dir) /= Directory then
         raise Constraint_Error with Dir & ": interface search dir does not exist";
      end if;

      Start_Search
        (Search,
         Directory => Dir,
         Pattern   => "*.safei.json",
         Filter    => (Ordinary_File => True, Directory => False, Special_File => False));
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Dir_Entry);
         Result.Append (Full_Name (Dir_Entry));
      end loop;
      End_Search (Search);

      if Result.Length > 1 then
         for I in Result.First_Index .. Result.Last_Index loop
            for J in I + 1 .. Result.Last_Index loop
               if Result (J) < Result (I) then
                  declare
                     Temp : constant String := Result (I);
                  begin
                     Result.Replace_Element (I, Result (J));
                     Result.Replace_Element (J, Temp);
                  end;
               end if;
            end loop;
         end loop;
      end if;
      return Result;
   end Discover_Interface_Files;

   function Parse_Interface_File
     (File_Path : String;
      Unit_Path : String) return Loaded_Interface
   is
      use GNATCOLL.JSON;

      Parsed : constant Read_Result := Read_File (File_Path);
      Root   : JSON_Value;
      Result : Loaded_Interface;
      Types  : JSON_Array;
   begin
      if not Parsed.Success then
         raise Constraint_Error with
           File_Path & ": invalid JSON: " & Format_Parsing_Error (Parsed.Error);
      end if;

      Root := Parsed.Value;
      if Root.Kind /= JSON_Object_Type then
         raise Constraint_Error with File_Path & ": top-level payload must be an object";
      end if;
      if Require_String (Root, "format", File_Path) /= "safei-v1" then
         raise Constraint_Error with File_Path & ": format must be safei-v1";
      end if;

      Result.Package_Name := FT.To_UString (Require_String (Root, "package_name", File_Path));

      Validate_Name_List (Require_Array (Root, "dependencies", File_Path), "dependencies", File_Path);
      Validate_Decl_List (Require_Array (Root, "executables", File_Path), "executables", File_Path);
      Validate_Decl_List (Require_Array (Root, "public_declarations", File_Path), "public_declarations", File_Path);

      Types := Require_Array (Root, "types", File_Path);
      for Index in 1 .. Length (Types) loop
         Result.Types.Append (Require_Type_Value (Get (Types, Index), "types[]", File_Path));
      end loop;

      Types := Require_Array (Root, "subtypes", File_Path);
      for Index in 1 .. Length (Types) loop
         Result.Subtypes.Append (Require_Type_Value (Get (Types, Index), "subtypes[]", File_Path));
      end loop;

      declare
         Channels : constant JSON_Array := Require_Array (Root, "channels", File_Path);
         Objects  : constant JSON_Array := Require_Array (Root, "objects", File_Path);
         Subps    : constant JSON_Array := Require_Array (Root, "subprograms", File_Path);
      begin
         for Index in 1 .. Length (Channels) loop
            declare
               Item    : constant JSON_Value := Get (Channels, Index);
               Channel : CM.Resolved_Channel_Decl;
            begin
               Channel.Name := FT.To_UString (Require_String (Item, "name", File_Path));
               Channel.Is_Public := Require_Boolean (Item, "is_public", File_Path);
               Channel.Element_Type :=
                 Require_Type_Field (Item, "element_type", "channels[].element_type", File_Path);
               Channel.Capacity := Require_Positive_Int (Item, "capacity", File_Path);
               Channel.Span := Parse_Span (Field_Or_Null (Item, "span"));
               Result.Channels.Append (Channel);
            end;
         end loop;

         for Index in 1 .. Length (Objects) loop
            declare
               Item   : constant JSON_Value := Get (Objects, Index);
               Object : Imported_Object;
               Kind   : constant JSON_Value := Field_Or_Null (Item, "static_value_kind");
               Value  : constant JSON_Value := Field_Or_Null (Item, "static_value");
            begin
               Object.Name := FT.To_UString (Require_String (Item, "name", File_Path));
               Object.Type_Info := Require_Type_Field (Item, "type", "objects[].type", File_Path);
               if Has_Field (Item, "is_constant") then
                  if Get (Item, "is_constant").Kind = JSON_Boolean_Type then
                     Object.Is_Constant := Get (Get (Item, "is_constant"));
                  else
                     raise Constraint_Error with File_Path & ": objects[].is_constant must be a boolean";
                  end if;
               end if;
               if Kind.Kind /= JSON_Null_Type and then not Object.Is_Constant then
                  raise Constraint_Error with
                    File_Path & ": objects[].static_value_kind requires is_constant = true";
               end if;
               if Value.Kind /= JSON_Null_Type and then Kind.Kind = JSON_Null_Type then
                  raise Constraint_Error with
                    File_Path & ": objects[].static_value requires static_value_kind";
               end if;
               if Kind.Kind /= JSON_Null_Type then
                  if Kind.Kind /= JSON_String_Type then
                     raise Constraint_Error with
                       File_Path & ": objects[].static_value_kind must be a string";
                  elsif Get (Kind) = "integer" then
                     if Value.Kind /= JSON_Int_Type then
                        raise Constraint_Error with
                          File_Path & ": objects[].static_value must be an integer";
                     end if;
                     declare
                        Int_Value : constant Long_Long_Integer := Get (Value);
                     begin
                        Object.Static_Info.Kind := CM.Static_Value_Integer;
                        Object.Static_Info.Int_Value := CM.Wide_Integer (Int_Value);
                     end;
                  elsif Get (Kind) = "boolean" then
                     if Value.Kind /= JSON_Boolean_Type then
                        raise Constraint_Error with
                          File_Path & ": objects[].static_value must be a boolean";
                     end if;
                     Object.Static_Info.Kind := CM.Static_Value_Boolean;
                     Object.Static_Info.Bool_Value := Get (Value);
                  else
                     raise Constraint_Error with
                       File_Path & ": objects[].static_value_kind must be `integer` or `boolean`";
                  end if;
               end if;
               Object.Span := Parse_Span (Field_Or_Null (Item, "span"));
               Result.Objects.Append (Object);
            end;
         end loop;

         for Index in 1 .. Length (Subps) loop
            declare
               Item   : constant JSON_Value := Get (Subps, Index);
               Subp   : Imported_Subprogram;
               Params : constant JSON_Array := Require_Array (Item, "params", File_Path);
            begin
               Subp.Name := FT.To_UString (Require_String (Item, "name", File_Path));
               Subp.Kind := FT.To_UString (Require_String (Item, "kind", File_Path));
               Subp.Signature := FT.To_UString (Require_String (Item, "signature", File_Path));
               Subp.Span := Parse_Span (Field_Or_Null (Item, "span"));
               if Has_Field (Item, "has_return_type")
                 and then Get (Item, "has_return_type").Kind = JSON_Boolean_Type
               then
                  Subp.Has_Return_Type := Get (Get (Item, "has_return_type"));
               else
                  raise Constraint_Error with File_Path & ": subprograms[].has_return_type must be a boolean";
               end if;
               if Has_Field (Item, "return_is_access_def")
                 and then Get (Item, "return_is_access_def").Kind = JSON_Boolean_Type
               then
                  Subp.Return_Is_Access_Def := Get (Get (Item, "return_is_access_def"));
               else
                  raise Constraint_Error with File_Path & ": subprograms[].return_is_access_def must be a boolean";
               end if;
               if Subp.Has_Return_Type then
                  Subp.Return_Type :=
                    Require_Type_Field
                      (Item,
                       "return_type",
                       "subprograms[].return_type",
                       File_Path);
               end if;
               for Param_Index in 1 .. Length (Params) loop
                  declare
                     Param_Item : constant JSON_Value := Get (Params, Param_Index);
                     Symbol     : CM.Symbol;
                  begin
                     Symbol.Name := FT.To_UString (Require_String (Param_Item, "name", File_Path));
                     Symbol.Kind := FT.To_UString ("param");
                     Symbol.Mode := FT.To_UString (Require_String (Param_Item, "mode", File_Path));
                     Symbol.Type_Info :=
                       Require_Type_Field
                         (Param_Item,
                          "type",
                          "subprograms[].params[].type",
                          File_Path);
                     Symbol.Span := Parse_Span (Field_Or_Null (Param_Item, "span"));
                     Subp.Params.Append (Symbol);
                  end;
               end loop;
               Result.Subprograms.Append (Subp);
            end;
         end loop;
      end;

      Validate_Effect_Summaries (Require_Array (Root, "effect_summaries", File_Path), File_Path);
      Validate_Channel_Summaries (Require_Array (Root, "channel_access_summaries", File_Path), File_Path);

      pragma Unreferenced (Unit_Path);
      return Result;
   end Parse_Interface_File;

   function Load_Dependencies
     (Search_Dirs : FT.UString_Vectors.Vector;
      Withs       : CM.With_Clause_Vectors.Vector;
      Path        : String) return Load_Result
   is
      Required : Span_Maps.Map;
      Result   : Loaded_Interface_Vectors.Vector;
      Loaded   : String_Maps.Map;
   begin
      for Clause of Withs loop
         for Name of Clause.Names loop
            declare
               Canon : constant String := Canonical (FT.To_String (Name));
            begin
               if not Required.Contains (Canon) then
                  Required.Include (Canon, Clause.Span);
               end if;
            end;
         end loop;
      end loop;

      if Required.Is_Empty then
         return (Success => True, Interfaces => Result);
      end if;

      for Dir of Search_Dirs loop
         declare
            Dir_Items : String_Maps.Map;
            Files     : constant String_Vectors.Vector := Discover_Interface_Files (FT.To_String (Dir));
         begin
            if not Files.Is_Empty then
               for File_Path of Files loop
                  declare
                     Item  : constant Loaded_Interface := Parse_Interface_File (File_Path, Path);
                     Canon : constant String := Canonical (FT.To_String (Item.Package_Name));
                  begin
                     if Dir_Items.Contains (Canon) then
                        return
                          (Success => False,
                           Diagnostic =>
                             CM.Source_Frontend_Error
                               (Path    => Path,
                                Span    => FT.Null_Span,
                                Message =>
                                  "duplicate interface for package `" & FT.To_String (Item.Package_Name)
                                  & "` in search dir `" & FT.To_String (Dir) & "`"));
                     end if;
                     Dir_Items.Include (Canon, Item);
                  end;
               end loop;
            end if;

            declare
               Cursor : Span_Maps.Cursor := Required.First;
            begin
               while Span_Maps.Has_Element (Cursor) loop
                  declare
                     Canon : constant String := Span_Maps.Key (Cursor);
                  begin
                     if not Loaded.Contains (Canon) and then Dir_Items.Contains (Canon) then
                        Loaded.Include (Canon, Dir_Items.Element (Canon));
                        Result.Append (Dir_Items.Element (Canon));
                     end if;
                     Span_Maps.Next (Cursor);
                  end;
               end loop;
            end;
         exception
            when Error : Constraint_Error =>
               return
                 (Success => False,
                  Diagnostic =>
                    CM.Source_Frontend_Error
                      (Path    => Path,
                       Span    => FT.Null_Span,
                       Message => Ada.Exceptions.Exception_Message (Error)));
         end;
      end loop;

      declare
         Cursor : Span_Maps.Cursor := Required.First;
      begin
         while Span_Maps.Has_Element (Cursor) loop
            declare
               Canon : constant String := Span_Maps.Key (Cursor);
            begin
               if not Loaded.Contains (Canon) then
                  return
                    (Success => False,
                     Diagnostic =>
                       CM.Source_Frontend_Error
                         (Path    => Path,
                          Span    => Span_Maps.Element (Cursor),
                          Message =>
                            "missing dependency interface for package `" & Canon & "`"));
               end if;
               Span_Maps.Next (Cursor);
            end;
         end loop;
      end;

      return (Success => True, Interfaces => Result);
   end Load_Dependencies;
end Safe_Frontend.Interfaces;
