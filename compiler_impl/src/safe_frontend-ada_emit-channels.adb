with Safe_Frontend.Ada_Emit.Statements;
with Safe_Frontend.Ada_Emit.Types;

package body Safe_Frontend.Ada_Emit.Channels is
   use AI;

   package AET renames Safe_Frontend.Ada_Emit.Types;
   package AES renames Safe_Frontend.Ada_Emit.Statements;
   use AET;
   use AES;

   use type FT.UString;

   function Channel_Uses_Environment_Task
     (Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      if Bronze.Graphs.Is_Empty then
         return False;
      end if;

      for Graph of Bronze.Graphs loop
         --  Bronze summaries already fold transitive callees into the unit
         --  initializer graph, so restricting this check to unit_init avoids
         --  over-raising ceilings for task-only helper subprograms.
         if FT.To_String (Graph.Kind) = "unit_init" then
            for Channel_Name of Graph.Channels loop
               if FT.To_String (Channel_Name) = Name then
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Channel_Uses_Environment_Task;
   function Channel_Uses_Unspecified_Task_Priority
     (Unit   : CM.Resolved_Unit;
      Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      for Item of Bronze.Ceilings loop
         if FT.To_String (Item.Channel_Name) = Name then
            for Task_Name of Item.Task_Names loop
               for Task_Item of Unit.Tasks loop
                  if FT.To_String (Task_Item.Name) = FT.To_String (Task_Name)
                    and then not Task_Item.Has_Explicit_Priority
                  then
                     return True;
                  end if;
               end loop;
            end loop;
            exit;
         end if;
      end loop;

      return False;
   end Channel_Uses_Unspecified_Task_Priority;
   function Shared_Uses_Environment_Task
     (Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      if Bronze.Graphs.Is_Empty then
         return False;
      end if;

      for Graph of Bronze.Graphs loop
         if FT.To_String (Graph.Kind) = "unit_init" then
            for Shared_Name of Graph.Shareds loop
               if FT.To_String (Shared_Name) = Name then
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Shared_Uses_Environment_Task;
   function Shared_Uses_Unspecified_Task_Priority
     (Unit   : CM.Resolved_Unit;
      Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      for Item of Bronze.Shared_Ceilings loop
         if FT.To_String (Item.Shared_Name) = Name then
            for Task_Name of Item.Task_Names loop
               for Task_Item of Unit.Tasks loop
                  if FT.To_String (Task_Item.Name) = FT.To_String (Task_Name)
                    and then not Task_Item.Has_Explicit_Priority
                  then
                     return True;
                  end if;
               end loop;
            end loop;
            exit;
         end if;
      end loop;

      return False;
   end Shared_Uses_Unspecified_Task_Priority;
   function Shared_Required_Ceiling
     (Bronze : MB.Bronze_Result;
      Name   : String) return Long_Long_Integer
   is
   begin
      for Item of Bronze.Shared_Ceilings loop
         if FT.To_String (Item.Shared_Name) = Name then
            return Item.Priority;
         end if;
      end loop;

      return 0;
   end Shared_Required_Ceiling;
   function Is_Plain_Shared_Nested_Record
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Name_Text : constant String := FT.Lowercase (FT.To_String (Base.Name));
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "record"
        and then not Base.Has_Discriminant
        and then Base.Discriminants.Is_Empty
        and then Base.Variant_Fields.Is_Empty
        and then not Base.Is_Result_Builtin
        and then not (Name_Text'Length > 11 and then Name_Text (Name_Text'First .. Name_Text'First + 10) = "__optional_");
   end Is_Plain_Shared_Nested_Record;
   procedure Render_Shared_Object_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State)
   is
      Root_Name     : constant String := FT.To_String (Decl.Names (Decl.Names.First_Index));
      Wrapper_Name  : constant String := Shared_Wrapper_Object_Name (Root_Name);
      Type_Name     : constant String := Shared_Wrapper_Type_Name (Root_Name);
      Record_Type   : constant String := Render_Type_Name (Decl.Type_Info);
      Record_Default : constant String := Default_Value_Expr (Unit, Document, Decl.Type_Info);
      Base_Info     : constant GM.Type_Descriptor := Base_Type (Unit, Document, Decl.Type_Info);
      Integer_Type_Name : constant String :=
        Render_Type_Name (Resolve_Type_Name (Unit, Document, "integer"));
      Is_Public_Shared : constant Boolean := Decl.Is_Public;
      Uses_Environment_Ceiling : constant Boolean :=
        Decl.Is_Public
        or else Shared_Uses_Environment_Task (Bronze, Root_Name)
        or else Shared_Uses_Unspecified_Task_Priority (Unit, Bronze, Root_Name);
      Ceiling : constant Long_Long_Integer :=
        Shared_Required_Ceiling (Bronze, Root_Name);
      Is_Container_Root : constant Boolean :=
        Is_Growable_Array_Type (Unit, Document, Decl.Type_Info);
      Element_Info : constant GM.Type_Descriptor :=
        (if Is_Container_Root
         then Resolve_Type_Name (Unit, Document, FT.To_String (Base_Info.Component_Type))
         else (others => <>));
      Key_Info     : GM.Type_Descriptor := (others => <>);
      Value_Info   : GM.Type_Descriptor := (others => <>);

      function Optional_Type_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Render_Type_Name_From_Text
             (Unit,
              Document,
              "__optional_" & Sanitize_Type_Name_Component (FT.To_String (Info.Name)),
              State);
      end Optional_Type_Name;

      function Public_Helper_Name (Operation : String) return String is
      begin
         return Shared_Public_Helper_Name (Root_Name, Operation);
      end Public_Helper_Name;

      function Public_Shared_Function_Suffix return String is
      begin
         return " with Volatile_Function";
      end Public_Shared_Function_Suffix;

      procedure Append_Nested_Setter_Specs
        (Info       : GM.Type_Descriptor;
         Path_Names : FT.UString_Vectors.Vector)
      is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      begin
         for Field of Base.Fields loop
            declare
               Next_Path       : FT.UString_Vectors.Vector := Path_Names;
               Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
               Field_Info      : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, Field_Type_Name);
            begin
               Next_Path.Append (Field.Name);
               if Natural (Next_Path.Length) >= 2 then
                  Append_Line
                    (Buffer,
                     "procedure "
                     & (if Is_Public_Shared
                        then Public_Helper_Name
                          (Shared_Nested_Field_Setter_Name (Next_Path))
                        else Shared_Nested_Field_Setter_Name (Next_Path))
                     & " (Value : in "
                     & Render_Type_Name_From_Text (Unit, Document, Field_Type_Name, State)
                     & ");",
                     (if Is_Public_Shared then 1 else 2));
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & (if Is_Public_Shared
                           then Public_Helper_Name
                             (Shared_Nested_Field_Setter_Name (Next_Path))
                           else Shared_Nested_Field_Setter_Name (Next_Path))
                        & " (Value : in String);",
                        (if Is_Public_Shared then 1 else 2));
                  end if;
               end if;

               if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                  Append_Nested_Setter_Specs (Field_Info, Next_Path);
               end if;
            end;
         end loop;
      end Append_Nested_Setter_Specs;
   begin
      if Is_Public_Shared then
         Append_Line
           (Buffer,
            "function " & Public_Helper_Name (Shared_Get_All_Name)
            & " return " & Record_Type
            & Public_Shared_Function_Suffix
            & ";",
            1);
         Append_Line
           (Buffer,
            "procedure " & Public_Helper_Name (Shared_Set_All_Name)
            & " (Value : in " & Record_Type & ");",
            1);
         if Is_Container_Root then
            Append_Line
              (Buffer,
               "function " & Public_Helper_Name (Shared_Get_Length_Name)
               & " return " & Integer_Type_Name
               & Public_Shared_Function_Suffix
               & ";",
               1);
            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Contains_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return boolean"
                  & Public_Shared_Function_Suffix
                  & ";",
                  1);
               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Get_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return " & Optional_Type_Name (Value_Info)
                  & Public_Shared_Function_Suffix
                  & ";",
                  1);
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Set_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Value : in " & Render_Type_Name (Value_Info) & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Remove_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Result : out " & Optional_Type_Name (Value_Info) & ");",
                  1);
            else
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Append_Name)
                  & " (Value : in " & Render_Type_Name (Element_Info) & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Pop_Last_Name)
                  & " (Result : out " & Optional_Type_Name (Element_Info) & ");",
                  1);
            end if;
         else
            for Field of Base_Info.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
                  Field_Type_Name : constant String :=
                    Render_Type_Name_From_Text
                      (Unit,
                       Document,
                       FT.To_String (Field.Type_Name),
                       State);
               begin
                  Append_Line
                    (Buffer,
                     "function "
                     & Public_Helper_Name
                         (Shared_Field_Getter_Name (FT.To_String (Field.Name)))
                     & " return "
                     & Field_Type_Name
                     & Public_Shared_Function_Suffix
                     & ";",
                     1);
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Public_Helper_Name
                         (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                     & " (Value : in "
                     & Field_Type_Name
                     & ");",
                     1);
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Public_Helper_Name
                            (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                        & " (Value : in String);",
                        1);
                  end if;
               end;
            end loop;
            declare
               Empty_Path : FT.UString_Vectors.Vector;
            begin
               Append_Nested_Setter_Specs (Decl.Type_Info, Empty_Path);
            end;
         end if;
         Append_Line (Buffer);
         return;
      end if;

      Append_Line
        (Buffer,
         "protected type "
         & Type_Name
         & " with Priority => "
         & (if Uses_Environment_Ceiling or else Ceiling <= 0
            then "System.Any_Priority'Last"
            else Trim_Image (Ceiling))
         & " is",
         1);
      Append_Line
        (Buffer,
         "function " & Shared_Get_All_Name & " return " & Record_Type & ";",
         2);
      Append_Line
        (Buffer,
         "procedure " & Shared_Set_All_Name & " (Value : in " & Record_Type & ");",
         2);
      if Is_Container_Root then
         Append_Line
           (Buffer,
            "function " & Shared_Get_Length_Name & " return " & Integer_Type_Name & ";",
            2);
         if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
            Append_Line
              (Buffer,
               "function " & Shared_Contains_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & ") return boolean;",
               2);
            Append_Line
              (Buffer,
               "function " & Shared_Get_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & ") return "
               & Optional_Type_Name (Value_Info) & ";",
               2);
            Append_Line
              (Buffer,
               "procedure " & Shared_Set_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & "; Value : in "
               & Render_Type_Name (Value_Info) & ");",
               2);
            Append_Line
              (Buffer,
               "procedure " & Shared_Remove_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & "; Result : out "
               & Optional_Type_Name (Value_Info) & ");",
               2);
         else
            Append_Line
              (Buffer,
               "procedure " & Shared_Append_Name & " (Value : in "
               & Render_Type_Name (Element_Info) & ");",
               2);
            Append_Line
              (Buffer,
               "procedure " & Shared_Pop_Last_Name & " (Result : out "
               & Optional_Type_Name (Element_Info) & ");",
               2);
         end if;
      else
         for Field of Base_Info.Fields loop
            declare
               Field_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
               Field_Type_Name : constant String :=
                 Render_Type_Name_From_Text
                   (Unit,
                    Document,
                    FT.To_String (Field.Type_Name),
                    State);
            begin
               Append_Line
                 (Buffer,
                  "function "
                  & Shared_Field_Getter_Name (FT.To_String (Field.Name))
                  & " return "
                  & Field_Type_Name
                  & ";",
                  2);
               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                  & " (Value : in "
                  & Field_Type_Name
                  & ");",
                  2);
               if Is_Plain_String_Type (Unit, Document, Field_Info) then
                  State.Needs_Safe_String_RT := True;
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                     & " (Value : in String);",
                     2);
               end if;
            end;
         end loop;
         declare
            Empty_Path : FT.UString_Vectors.Vector;
         begin
            Append_Nested_Setter_Specs (Decl.Type_Info, Empty_Path);
         end;
      end if;
      Append_Line
        (Buffer,
         "procedure Initialize (Value : in " & Record_Type & ");",
         2);
      Append_Line (Buffer, "private", 1);
      Append_Line
        (Buffer,
         "State_Value : " & Record_Type & " := " & Record_Default & ";",
         2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer, Wrapper_Name & " : " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Shared_Object_Spec;
   procedure Render_Shared_Object_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State)
   is
      Root_Name    : constant String := FT.To_String (Decl.Names (Decl.Names.First_Index));
      Wrapper_Name : constant String := Shared_Wrapper_Object_Name (Root_Name);
      Type_Name    : constant String := Shared_Wrapper_Type_Name (Root_Name);
      Root_Type    : constant String := Render_Type_Name (Decl.Type_Info);
      Base_Info    : constant GM.Type_Descriptor := Base_Type (Unit, Document, Decl.Type_Info);
      Is_Public_Shared : constant Boolean := Decl.Is_Public;
      Heap_Root    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Decl.Type_Info);
      Is_Container_Root : constant Boolean :=
        Is_Growable_Array_Type (Unit, Document, Decl.Type_Info);
      Integer_Type_Name : constant String :=
        Render_Type_Name (Resolve_Type_Name (Unit, Document, "integer"));
      Uses_Environment_Ceiling : constant Boolean :=
        Decl.Is_Public
        or else Shared_Uses_Environment_Task (Bronze, Root_Name)
        or else Shared_Uses_Unspecified_Task_Priority (Unit, Bronze, Root_Name);
      Ceiling : constant Long_Long_Integer :=
        Shared_Required_Ceiling (Bronze, Root_Name);
      Key_Info     : GM.Type_Descriptor := (others => <>);
      Value_Info   : GM.Type_Descriptor := (others => <>);
      Generated_Shared_Helpers : FT.UString_Vectors.Vector;
      Runtime_Dependency_Types  : FT.UString_Vectors.Vector;

      function Optional_Type_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Render_Type_Name_From_Text
             (Unit,
              Document,
              "__optional_" & Sanitize_Type_Name_Component (FT.To_String (Info.Name)),
              State);
      end Optional_Type_Name;

      function Optional_Default_Expr (Info : GM.Type_Descriptor) return String is
      begin
         return Optional_Type_Name (Info) & "'(present => False)";
      end Optional_Default_Expr;

      function Public_Helper_Name (Operation : String) return String is
      begin
         return Shared_Public_Helper_Name (Root_Name, Operation);
      end Public_Helper_Name;

      function Shared_Copy_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Heap_Copy_Helper_Name
             (AI.Heap_Helper_Shared, Wrapper_Name, Unit, Document, Info);
      end Shared_Copy_Helper_Name;

      function Shared_Free_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Heap_Free_Helper_Name
             (AI.Heap_Helper_Shared, Wrapper_Name, Unit, Document, Info);
      end Shared_Free_Helper_Name;

      procedure Append_Copy_Value
        (Target_Text : String;
         Source_Text : String;
         Info        : GM.Type_Descriptor;
         Depth       : Natural) is
      begin
         Append_Heap_Copy_Value
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Target_Text,
            Source_Text,
            Info,
            Depth);
      end Append_Copy_Value;

      procedure Append_Free_Value
        (Target_Text : String;
         Info        : GM.Type_Descriptor;
         Depth       : Natural) is
      begin
         Append_Heap_Free_Value
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Target_Text,
            Info,
            Depth);
      end Append_Free_Value;

      procedure Render_Shared_Value_Helpers (Info : GM.Type_Descriptor);

      procedure Render_Shared_Value_Helpers (Info : GM.Type_Descriptor) is
         Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         Kind      : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Type_Key  : constant String := Render_Type_Name (Info);
         Type_Name : constant String := Render_Type_Name (Info);

         procedure Ensure_Helper (Name_Text : String) is
         begin
            if Name_Text'Length = 0 then
               return;
            end if;

            Render_Shared_Value_Helpers
              (Resolve_Type_Name (Unit, Document, Name_Text));
         end Ensure_Helper;
      begin
         if Contains_Name (Generated_Shared_Helpers, Type_Key) then
            return;
         end if;

         if not Needs_Generated_Heap_Helper (Unit, Document, Info) then
            if Is_Growable_Array_Type (Unit, Document, Base)
              and then Base.Has_Component_Type
            then
               Ensure_Helper (FT.To_String (Base.Component_Type));
            end if;
            return;
         end if;

         if Starts_With (FT.To_String (Base.Name), "__optional_") then
            declare
               Payload_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String
                      (Base.Variant_Fields (Base.Variant_Fields.First_Index).Type_Name));
            begin
               Ensure_Helper
                 (FT.To_String
                    (Base.Variant_Fields (Base.Variant_Fields.First_Index).Type_Name));
               Generated_Shared_Helpers.Append (FT.To_UString (Type_Key));

               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Copy_Helper_Name (Info)
                  & " (Target : out "
                  & Type_Name
                  & "; Source : "
                  & Type_Name
                  & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Copy_Helper_Name (Info)
                  & " (Target : out "
                  & Type_Name
                  & "; Source : "
                  & Type_Name
                  & ") is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line (Buffer, "Target := Source;", 2);
               Append_Line (Buffer, "if Source.present then", 2);
               Append_Heap_Copy_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  AI.Heap_Helper_Shared,
                  Wrapper_Name,
                  "Target.value",
                  "Source.value",
                  Payload_Info,
                  3);
               Append_Line (Buffer, "end if;", 2);
               Append_Line (Buffer, "end " & Shared_Copy_Helper_Name (Info) & ";", 1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Free_Helper_Name (Info)
                  & " (Value : in out "
                  & Type_Name
                  & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Free_Helper_Name (Info)
                  & " (Value : in out "
                  & Type_Name
                  & ") is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line (Buffer, "if Value.present then", 2);
               Append_Heap_Free_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  AI.Heap_Helper_Shared,
                  Wrapper_Name,
                  "Value.value",
                  Payload_Info,
                  3);
               Append_Line (Buffer, "end if;", 2);
               Append_Line
                 (Buffer,
                  "Value := " & Default_Value_Expr (Unit, Document, Info) & ";",
                  2);
               Append_Line (Buffer, "end " & Shared_Free_Helper_Name (Info) & ";", 1);
               Append_Line (Buffer);
               return;
            end;
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

         Generated_Shared_Helpers.Append (FT.To_UString (Type_Key));

         Append_Line
           (Buffer,
            "procedure "
            & Shared_Copy_Helper_Name (Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Shared_Copy_Helper_Name (Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Copy_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Info,
            2);
         Append_Line (Buffer, "end " & Shared_Copy_Helper_Name (Info) & ";", 1);
         Append_Line (Buffer);

         Append_Line
           (Buffer,
            "procedure "
            & Shared_Free_Helper_Name (Info)
            & " (Value : in out "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Shared_Free_Helper_Name (Info)
            & " (Value : in out "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Free_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Info,
            2);
         Append_Line
           (Buffer,
            "Value := " & Default_Value_Expr (Unit, Document, Info) & ";",
            2);
         Append_Line (Buffer, "end " & Shared_Free_Helper_Name (Info) & ";", 1);
         Append_Line (Buffer);
      end Render_Shared_Value_Helpers;

      procedure Append_Nested_Setter_Bodies
        (Info       : GM.Type_Descriptor;
         Path_Names : FT.UString_Vectors.Vector)
      is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      begin
         for Field of Base.Fields loop
            declare
               Next_Path       : FT.UString_Vectors.Vector := Path_Names;
               Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
               Field_Info      : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, Field_Type_Name);
               Field_Path      : SU.Unbounded_String := SU.To_Unbounded_String ("State_Value");
            begin
               Next_Path.Append (Field.Name);
               for Part of Next_Path loop
                  Field_Path := Field_Path & "." & FT.To_String (Part);
               end loop;

               if Natural (Next_Path.Length) >= 2 then
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Shared_Nested_Field_Setter_Name (Next_Path)
                     & " (Value : in "
                     & Render_Type_Name_From_Text (Unit, Document, Field_Type_Name, State)
                     & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line (Buffer, "begin", 2);
                  if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                     Append_Free_Value (SU.To_String (Field_Path), Field_Info, 3);
                     Append_Copy_Value
                       (SU.To_String (Field_Path),
                        "Value",
                        Field_Info,
                        3);
                  else
                     Append_Line (Buffer, SU.To_String (Field_Path) & " := Value;", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "end " & Shared_Nested_Field_Setter_Name (Next_Path) & ";",
                     2);
                  Append_Line (Buffer);
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Value : in String) is",
                        2);
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                     Append_Line (Buffer, "begin", 2);
                     Append_Line
                       (Buffer,
                        Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Safe_String_RT.From_Literal (Value));",
                        3);
                     Append_Line
                       (Buffer,
                        "end " & Shared_Nested_Field_Setter_Name (Next_Path) & ";",
                        2);
                     Append_Line (Buffer);
                  end if;
               end if;

               if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                  Append_Nested_Setter_Bodies (Field_Info, Next_Path);
               end if;
            end;
         end loop;
      end Append_Nested_Setter_Bodies;

      procedure Append_Private_Wrapper_Declarations is
         Record_Default : constant String :=
           Default_Value_Expr (Unit, Document, Decl.Type_Info);

         procedure Append_Nested_Setter_Specs
           (Info       : GM.Type_Descriptor;
            Path_Names : FT.UString_Vectors.Vector)
         is
            Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         begin
            for Field of Base.Fields loop
               declare
                  Next_Path       : FT.UString_Vectors.Vector := Path_Names;
                  Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
                  Field_Info      : constant GM.Type_Descriptor :=
                    (if Has_Type (Unit, Document, Field_Type_Name)
                     then Lookup_Type (Unit, Document, Field_Type_Name)
                     else (others => <>));
               begin
                  Next_Path.Append (Field.Name);
                  if Natural (Next_Path.Length) >= 2 then
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Value : in "
                        & Render_Type_Name_From_Text
                            (Unit,
                             Document,
                             Field_Type_Name,
                             State)
                        & ");",
                        2);
                     if Is_Plain_String_Type (Unit, Document, Field_Info) then
                        State.Needs_Safe_String_RT := True;
                        Append_Line
                          (Buffer,
                           "procedure "
                           & Shared_Nested_Field_Setter_Name (Next_Path)
                           & " (Value : in String);",
                           2);
                     end if;
                  end if;

                  if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                     Append_Nested_Setter_Specs (Field_Info, Next_Path);
                  end if;
               end;
            end loop;
         end Append_Nested_Setter_Specs;
      begin
         Append_Line
           (Buffer,
            "protected type "
            & Type_Name
            & " with Priority => "
            & (if Uses_Environment_Ceiling or else Ceiling <= 0
               then "System.Any_Priority'Last"
               else Trim_Image (Ceiling))
            & " is",
            1);
         Append_Line
           (Buffer,
            "function " & Shared_Get_All_Name & " return " & Root_Type & ";",
            2);
         Append_Line
           (Buffer,
            "procedure " & Shared_Set_All_Name & " (Value : in " & Root_Type & ");",
            2);
         if Is_Container_Root then
            Append_Line
              (Buffer,
               "function " & Shared_Get_Length_Name & " return "
               & Integer_Type_Name & ";",
               2);
            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               Append_Line
                 (Buffer,
                  "function " & Shared_Contains_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & ") return boolean;",
                  2);
               Append_Line
                 (Buffer,
                  "function " & Shared_Get_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & ") return "
                  & Optional_Type_Name (Value_Info) & ";",
                  2);
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Set_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & "; Value : in "
                  & Render_Type_Name (Value_Info) & ");",
                  2);
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Remove_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & "; Result : out "
                  & Optional_Type_Name (Value_Info) & ");",
                  2);
            else
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Append_Name & " (Value : in "
                  & Render_Type_Name (Resolve_Type_Name
                    (Unit,
                     Document,
                     FT.To_String (Base_Info.Component_Type))) & ");",
                  2);
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Pop_Last_Name & " (Result : out "
                  & Optional_Type_Name
                      (Resolve_Type_Name
                         (Unit,
                          Document,
                          FT.To_String (Base_Info.Component_Type)))
                  & ");",
                  2);
            end if;
         else
            for Field of Base_Info.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
                  Field_Type_Name : constant String :=
                    Render_Type_Name_From_Text
                      (Unit,
                       Document,
                       FT.To_String (Field.Type_Name),
                       State);
               begin
                  Append_Line
                    (Buffer,
                     "function "
                     & Shared_Field_Getter_Name (FT.To_String (Field.Name))
                     & " return "
                     & Field_Type_Name
                     & ";",
                     2);
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                     & " (Value : in "
                     & Field_Type_Name
                     & ");",
                     2);
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                        & " (Value : in String);",
                        2);
                  end if;
               end;
            end loop;
            declare
               Empty_Path : FT.UString_Vectors.Vector;
            begin
               Append_Nested_Setter_Specs (Decl.Type_Info, Empty_Path);
            end;
         end if;
         Append_Line
           (Buffer,
            "procedure Initialize (Value : in " & Root_Type & ");",
            2);
         Append_Line (Buffer, "private", 1);
         Append_Line
           (Buffer,
            "State_Value : " & Root_Type & " := " & Record_Default & ";",
            2);
         Append_Line (Buffer, "end " & Type_Name & ";", 1);
         Append_Line (Buffer, Wrapper_Name & " : " & Type_Name & ";", 1);
         Append_Line (Buffer);
      end Append_Private_Wrapper_Declarations;

      procedure Append_Public_Helper_Bodies is
         procedure Append_Public_Nested_Setter_Bodies
           (Info       : GM.Type_Descriptor;
            Path_Names : FT.UString_Vectors.Vector)
         is
            Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         begin
            for Field of Base.Fields loop
               declare
                  Next_Path       : FT.UString_Vectors.Vector := Path_Names;
                  Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
                  Field_Info      : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, Field_Type_Name);
               begin
                  Next_Path.Append (Field.Name);
                  if Natural (Next_Path.Length) >= 2 then
                     Append_Line
                       (Buffer,
                        "procedure " & Public_Helper_Name
                          (Shared_Nested_Field_Setter_Name (Next_Path))
                        & " (Value : in "
                        & Render_Type_Name_From_Text
                            (Unit,
                             Document,
                             Field_Type_Name,
                             State)
                        & ") is",
                        1);
                     Append_Line (Buffer, "begin", 1);
                     Append_Line
                       (Buffer,
                        Wrapper_Name & "." & Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Value);",
                        2);
                     Append_Line
                       (Buffer,
                        "end " & Public_Helper_Name
                          (Shared_Nested_Field_Setter_Name (Next_Path)) & ";",
                        1);
                     Append_Line (Buffer);
                     if Is_Plain_String_Type (Unit, Document, Field_Info) then
                        State.Needs_Safe_String_RT := True;
                        Append_Line
                          (Buffer,
                           "procedure " & Public_Helper_Name
                             (Shared_Nested_Field_Setter_Name (Next_Path))
                           & " (Value : in String) is",
                           1);
                        Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
                        Append_Line (Buffer, "begin", 1);
                        Append_Line
                          (Buffer,
                           Wrapper_Name & "." & Shared_Nested_Field_Setter_Name (Next_Path)
                           & " (Safe_String_RT.From_Literal (Value));",
                           2);
                        Append_Line
                          (Buffer,
                           "end " & Public_Helper_Name
                             (Shared_Nested_Field_Setter_Name (Next_Path)) & ";",
                           1);
                        Append_Line (Buffer);
                     end if;
                  end if;

                  if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                     Append_Public_Nested_Setter_Bodies (Field_Info, Next_Path);
                  end if;
               end;
            end loop;
         end Append_Public_Nested_Setter_Bodies;
      begin
         Append_Line
           (Buffer,
            "function " & Public_Helper_Name (Shared_Get_All_Name)
            & " return " & Root_Type & " is",
            1);
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
         Append_Line (Buffer, "begin", 1);
         Append_Line
           (Buffer,
            "return " & Wrapper_Name & "." & Shared_Get_All_Name & ";",
            2);
         Append_Line
           (Buffer,
            "end " & Public_Helper_Name (Shared_Get_All_Name) & ";",
            1);
         Append_Line (Buffer);

         Append_Line
           (Buffer,
            "procedure " & Public_Helper_Name (Shared_Set_All_Name)
            & " (Value : in " & Root_Type & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line
           (Buffer,
            Wrapper_Name & "." & Shared_Set_All_Name & " (Value);",
            2);
         Append_Line
           (Buffer,
            "end " & Public_Helper_Name (Shared_Set_All_Name) & ";",
            1);
         Append_Line (Buffer);

         if Is_Container_Root then
            Append_Line
              (Buffer,
               "function " & Public_Helper_Name (Shared_Get_Length_Name)
               & " return " & Integer_Type_Name & " is",
               1);
            Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
            Append_Line (Buffer, "begin", 1);
            Append_Line
              (Buffer,
               "return " & Wrapper_Name & "." & Shared_Get_Length_Name & ";",
               2);
            Append_Line
              (Buffer,
               "end " & Public_Helper_Name (Shared_Get_Length_Name) & ";",
               1);
            Append_Line (Buffer);

            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Contains_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return boolean is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  "return " & Wrapper_Name & "." & Shared_Contains_Name
                  & " (Key);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Contains_Name) & ";",
                  1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Get_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return " & Optional_Type_Name (Value_Info)
                  & " is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  "return " & Wrapper_Name & "." & Shared_Get_Name
                  & " (Key);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Get_Name) & ";",
                  1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Set_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Value : in " & Render_Type_Name (Value_Info)
                  & ") is",
                  1);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  Wrapper_Name & "." & Shared_Set_Name & " (Key, Value);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Set_Name) & ";",
                  1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Remove_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Result : out "
                  & Optional_Type_Name (Value_Info)
                  & ") is",
                  1);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  Wrapper_Name & "." & Shared_Remove_Name
                  & " (Key, Result);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Remove_Name) & ";",
                  1);
               Append_Line (Buffer);
            else
               declare
                  Element_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Base_Info.Component_Type));
               begin
                  Append_Line
                    (Buffer,
                     "procedure " & Public_Helper_Name (Shared_Append_Name)
                     & " (Value : in " & Render_Type_Name (Element_Info)
                     & ") is",
                     1);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     Wrapper_Name & "." & Shared_Append_Name & " (Value);",
                     2);
                  Append_Line
                    (Buffer,
                     "end " & Public_Helper_Name (Shared_Append_Name) & ";",
                     1);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Public_Helper_Name (Shared_Pop_Last_Name)
                     & " (Result : out "
                     & Optional_Type_Name (Element_Info)
                     & ") is",
                     1);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     Wrapper_Name & "." & Shared_Pop_Last_Name
                     & " (Result);",
                     2);
                  Append_Line
                    (Buffer,
                     "end " & Public_Helper_Name (Shared_Pop_Last_Name) & ";",
                     1);
                  Append_Line (Buffer);
               end;
            end if;
         else
            for Field of Base_Info.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
                  Field_Type_Name : constant String :=
                    Render_Type_Name_From_Text
                      (Unit,
                       Document,
                       FT.To_String (Field.Type_Name),
                       State);
               begin
                  Append_Line
                    (Buffer,
                     "function "
                     & Public_Helper_Name
                         (Shared_Field_Getter_Name (FT.To_String (Field.Name)))
                     & " return "
                     & Field_Type_Name
                     & " is",
                     1);
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     "return " & Wrapper_Name & "."
                     & Shared_Field_Getter_Name (FT.To_String (Field.Name))
                     & ";",
                     2);
                  Append_Line
                    (Buffer,
                     "end "
                     & Public_Helper_Name
                         (Shared_Field_Getter_Name (FT.To_String (Field.Name)))
                     & ";",
                     1);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure "
                     & Public_Helper_Name
                         (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                     & " (Value : in "
                     & Field_Type_Name
                     & ") is",
                     1);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     Wrapper_Name & "."
                     & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                     & " (Value);",
                     2);
                  Append_Line
                    (Buffer,
                     "end "
                     & Public_Helper_Name
                         (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                     & ";",
                     1);
                  Append_Line (Buffer);
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Public_Helper_Name
                            (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                        & " (Value : in String) is",
                        1);
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
                     Append_Line (Buffer, "begin", 1);
                     Append_Line
                       (Buffer,
                        Wrapper_Name & "."
                        & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                        & " (Safe_String_RT.From_Literal (Value));",
                        2);
                     Append_Line
                       (Buffer,
                        "end "
                        & Public_Helper_Name
                            (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                        & ";",
                        1);
                     Append_Line (Buffer);
                  end if;
               end;
            end loop;
            declare
               Empty_Path : FT.UString_Vectors.Vector;
            begin
               Append_Public_Nested_Setter_Bodies (Decl.Type_Info, Empty_Path);
            end;
         end if;
      end Append_Public_Helper_Bodies;
   begin
      if Is_Public_Shared then
         Append_Private_Wrapper_Declarations;
      end if;

      if Heap_Root then
         Append_Local_Warning_Suppression (Buffer, 1);
         Mark_Heap_Runtime_Dependencies
           (Unit,
            Document,
            Decl.Type_Info,
            State,
            Runtime_Dependency_Types);
         Render_Shared_Value_Helpers (Decl.Type_Info);
      end if;

      Append_Line (Buffer, "protected body " & Type_Name & " is", 1);
      Append_Line
        (Buffer,
         "function " & Shared_Get_All_Name & " return "
         & Root_Type & " is",
         2);
      if Heap_Root then
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
      end if;
      if Heap_Root then
         Append_Line
           (Buffer,
            "Result : " & Root_Type & " := "
            & Default_Value_Expr (Unit, Document, Decl.Type_Info)
            & ";",
            2);
      end if;
      Append_Line (Buffer, "begin", 2);
      if Heap_Root then
         if Is_Container_Root then
            Append_Copy_Value ("Result", "State_Value", Decl.Type_Info, 3);
         else
            Append_Line
              (Buffer,
               Shared_Copy_Helper_Name (Decl.Type_Info) & " (Result, State_Value);",
               3);
         end if;
         Append_Line (Buffer, "return Result;", 3);
      else
         Append_Line (Buffer, "return State_Value;", 3);
      end if;
      Append_Line (Buffer, "end " & Shared_Get_All_Name & ";", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure " & Shared_Set_All_Name & " (Value : in "
         & Root_Type & ") is",
         2);
      if Heap_Root then
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
      end if;
      Append_Line (Buffer, "begin", 2);
      if Heap_Root then
         Append_Free_Value ("State_Value", Decl.Type_Info, 3);
         if Is_Container_Root then
            Append_Copy_Value ("State_Value", "Value", Decl.Type_Info, 3);
         else
            Append_Line
              (Buffer,
               Shared_Copy_Helper_Name (Decl.Type_Info) & " (State_Value, Value);",
               3);
         end if;
      else
         Append_Line (Buffer, "State_Value := Value;", 3);
      end if;
      Append_Line (Buffer, "end " & Shared_Set_All_Name & ";", 2);
      Append_Line (Buffer);
      if Is_Container_Root then
         declare
            Runtime_Name : constant String := Array_Runtime_Instance_Name (Base_Info);
            Element_Free_Name : constant String :=
              Array_Runtime_Free_Element_Name (Base_Info);
            Element_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Base_Info.Component_Type));
            Key_Info     : GM.Type_Descriptor := (others => <>);
            Value_Info   : GM.Type_Descriptor := (others => <>);
         begin
            Append_Line
              (Buffer,
               "function " & Shared_Get_Length_Name & " return "
               & Integer_Type_Name & " is",
               2);
            Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
            Append_Line (Buffer, "begin", 2);
            Append_Line
              (Buffer,
               "return " & Integer_Type_Name & " (" & Runtime_Name & ".Length (State_Value));",
               3);
            Append_Line (Buffer, "end " & Shared_Get_Length_Name & ";", 2);
            Append_Line (Buffer);

            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               declare
                  Entry_Type_Name     : constant String := Render_Type_Name (Element_Info);
                  Key_Type_Name       : constant String := Render_Type_Name (Key_Info);
                  Value_Type_Name     : constant String := Render_Type_Name (Value_Info);
                  Optional_Value_Name : constant String :=
                    Optional_Type_Name (Value_Info);

                  function Key_Equality_Image
                    (Left_Image  : String;
                     Right_Image : String) return String
                  is
                     Base_Key : constant GM.Type_Descriptor :=
                       Base_Type (Unit, Document, Key_Info);
                     Key_Kind : constant String :=
                       FT.Lowercase (FT.To_String (Base_Key.Kind));
                     Key_Name : constant String :=
                       FT.Lowercase (FT.To_String (Base_Key.Name));
                  begin
                     if Is_Plain_String_Type (Unit, Document, Key_Info) then
                        return
                          "Safe_String_RT.To_String ("
                          & Left_Image
                          & ") = Safe_String_RT.To_String ("
                          & Right_Image
                          & ")";
                     elsif Is_Bounded_String_Type (Key_Info)
                       or else Key_Kind = "string"
                       or else Key_Name = "string"
                     then
                        return Left_Image & " = " & Right_Image;
                     end if;

                     return Left_Image & " = " & Right_Image;
                  end Key_Equality_Image;

                  procedure Ignore_Map_Extra_Decls (Depth : Natural) is
                     pragma Unreferenced (Depth);
                  begin
                     null;
                  end Ignore_Map_Extra_Decls;

                  generic
                     with procedure Append_Extra_Decls (Depth : Natural);
                     with procedure Append_On_Match (Depth : Natural);
                  procedure Append_Map_Search_Loop;

                  procedure Append_Map_Search_Loop is
                  begin
                     Append_Line (Buffer, "if Length_Value > 0 then", 3);
                     Append_Line
                       (Buffer,
                        "for Index in Positive range 1 .. Positive (Length_Value) loop",
                        4);
                     Append_Line (Buffer, "declare", 5);
                     Append_Line
                       (Buffer,
                        "Current_Entry : " & Entry_Type_Name & " := "
                        & Runtime_Name & ".Element (State_Value, Index);",
                        6);
                     Append_Extra_Decls (6);
                     Append_Line (Buffer, "begin", 5);
                     Append_Line
                       (Buffer,
                        "if "
                        & Key_Equality_Image
                          ("Current_Entry." & Tuple_Field_Name (1),
                           "Key")
                        & " then",
                        6);
                     Append_On_Match (7);
                     Append_Line (Buffer, "end if;", 6);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        6);
                     Append_Line (Buffer, "end;", 5);
                     Append_Line (Buffer, "end loop;", 4);
                     Append_Line (Buffer, "end if;", 3);
                  end Append_Map_Search_Loop;

                  procedure Append_Contains_Match (Depth : Natural) is
                  begin
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line (Buffer, "return True;", Depth);
                  end Append_Contains_Match;

                  procedure Append_Get_Match (Depth : Natural) is
                  begin
                     if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                        Append_Line (Buffer, "Result.present := True;", Depth);
                        Append_Copy_Value
                          ("Result.value",
                           "Current_Entry." & Tuple_Field_Name (2),
                           Value_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "Result := (present => True, value => Current_Entry." & Tuple_Field_Name (2) & ");",
                           Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line (Buffer, "return Result;", Depth);
                  end Append_Get_Match;

                  procedure Append_Set_Extra_Decls (Depth : Natural) is
                  begin
                     Append_Line
                       (Buffer,
                        "New_Entry : " & Entry_Type_Name & " := (others => <>);",
                        Depth);
                  end Append_Set_Extra_Decls;

                  procedure Append_Set_Match (Depth : Natural) is
                  begin
                     if Has_Heap_Value_Type (Unit, Document, Key_Info) then
                        Append_Copy_Value
                          ("New_Entry." & Tuple_Field_Name (1),
                           "Key",
                           Key_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "New_Entry." & Tuple_Field_Name (1) & " := Key;",
                           Depth);
                     end if;
                     if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                        Append_Copy_Value
                          ("New_Entry." & Tuple_Field_Name (2),
                           "Value",
                           Value_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "New_Entry." & Tuple_Field_Name (2) & " := Value;",
                           Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Runtime_Name & ".Replace_Element (State_Value, Index, New_Entry);",
                        Depth);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (New_Entry);",
                        Depth);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line (Buffer, "return;", Depth);
                  end Append_Set_Match;

                  procedure Append_Remove_Match (Depth : Natural) is
                  begin
                     if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                        Append_Line (Buffer, "Result.present := True;", Depth);
                        Append_Copy_Value
                          ("Result.value",
                           "Current_Entry." & Tuple_Field_Name (2),
                           Value_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "Result := (present => True, value => Current_Entry." & Tuple_Field_Name (2) & ");",
                           Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line
                       (Buffer,
                        "if Index < Positive (Length_Value) then",
                        Depth);
                     Append_Line (Buffer, "declare", Depth + 1);
                     Append_Line
                       (Buffer,
                        "Replacement_Entry : " & Entry_Type_Name & " := "
                        & Runtime_Name & ".Element (State_Value, Positive (Length_Value));",
                        Depth + 2);
                     Append_Line (Buffer, "begin", Depth + 1);
                     Append_Line
                       (Buffer,
                        Runtime_Name & ".Replace_Element (State_Value, Index, Replacement_Entry);",
                        Depth + 2);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Replacement_Entry);",
                        Depth + 2);
                     Append_Line (Buffer, "end;", Depth + 1);
                     Append_Line (Buffer, "end if;", Depth);
                     Append_Line (Buffer, "declare", Depth);
                     Append_Line
                       (Buffer,
                        "Updated : constant " & Root_Type & " := "
                        & "(if Length_Value = 1 then " & Runtime_Name & ".Empty else "
                        & Runtime_Name & ".Slice (State_Value, 1, Length_Value - 1));",
                        Depth + 1);
                     Append_Line (Buffer, "begin", Depth);
                     Append_Free_Value ("State_Value", Decl.Type_Info, Depth + 1);
                     Append_Line (Buffer, "State_Value := Updated;", Depth + 1);
                     Append_Line (Buffer, "end;", Depth);
                     Append_Line (Buffer, "return;", Depth);
                  end Append_Remove_Match;

                  procedure Append_Contains_Search_Loop is new Append_Map_Search_Loop
                    (Ignore_Map_Extra_Decls, Append_Contains_Match);
                  procedure Append_Get_Search_Loop is new Append_Map_Search_Loop
                    (Ignore_Map_Extra_Decls, Append_Get_Match);
                  procedure Append_Set_Search_Loop is new Append_Map_Search_Loop
                    (Append_Set_Extra_Decls, Append_Set_Match);
                  procedure Append_Remove_Search_Loop is new Append_Map_Search_Loop
                    (Ignore_Map_Extra_Decls, Append_Remove_Match);
               begin
                  Append_Line
                    (Buffer,
                     "function " & Shared_Contains_Name & " (Key : in "
                     & Key_Type_Name & ") return boolean is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Contains_Search_Loop;
                  Append_Line (Buffer, "return False;", 3);
                  Append_Line (Buffer, "end " & Shared_Contains_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "function " & Shared_Get_Name & " (Key : in "
                     & Key_Type_Name & ") return " & Optional_Value_Name & " is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line
                    (Buffer,
                     "Result : " & Optional_Value_Name & " := "
                     & Optional_Default_Expr (Value_Info) & ";",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Get_Search_Loop;
                  Append_Line (Buffer, "return Result;", 3);
                  Append_Line (Buffer, "end " & Shared_Get_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Set_Name & " (Key : in "
                     & Key_Type_Name & "; Value : in " & Value_Type_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Set_Search_Loop;
                  Append_Line (Buffer, "declare", 3);
                  Append_Line
                    (Buffer,
                     "New_Entry : " & Entry_Type_Name & " := (others => <>);",
                     4);
                  Append_Line (Buffer, "begin", 3);
                  if Has_Heap_Value_Type (Unit, Document, Key_Info) then
                     Append_Copy_Value
                       ("New_Entry." & Tuple_Field_Name (1),
                        "Key",
                        Key_Info,
                        4);
                  else
                     Append_Line
                       (Buffer,
                        "New_Entry." & Tuple_Field_Name (1) & " := Key;",
                        4);
                  end if;
                  if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                     Append_Copy_Value
                       ("New_Entry." & Tuple_Field_Name (2),
                        "Value",
                        Value_Info,
                        4);
                  else
                     Append_Line
                       (Buffer,
                        "New_Entry." & Tuple_Field_Name (2) & " := Value;",
                        4);
                  end if;
                  Append_Line (Buffer, "declare", 4);
                  Append_Line
                    (Buffer,
                     "Tail : " & Root_Type & " := "
                     & Runtime_Name & ".From_Array ((1 => New_Entry));",
                     5);
                  Append_Line
                    (Buffer,
                     "Updated : constant " & Root_Type & " := "
                     & Runtime_Name & ".Concat (State_Value, Tail);",
                     5);
                  Append_Line (Buffer, "begin", 4);
                  Append_Line
                    (Buffer,
                     Element_Free_Name & " (New_Entry);",
                     5);
                  Append_Free_Value ("State_Value", Decl.Type_Info, 5);
                  Append_Free_Value ("Tail", Decl.Type_Info, 5);
                  Append_Line (Buffer, "State_Value := Updated;", 5);
                  Append_Line (Buffer, "end;", 4);
                  Append_Line (Buffer, "end;", 3);
                  Append_Line (Buffer, "end " & Shared_Set_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Remove_Name & " (Key : in "
                     & Key_Type_Name & "; Result : out "
                     & Optional_Value_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Line
                    (Buffer,
                     "Result := " & Optional_Default_Expr (Value_Info) & ";",
                     3);
                  Append_Remove_Search_Loop;
                  Append_Line (Buffer, "end " & Shared_Remove_Name & ";", 2);
                  Append_Line (Buffer);
               end;
            else
               declare
                  Element_Type_Name     : constant String := Render_Type_Name (Element_Info);
                  Optional_Element_Name : constant String :=
                    Optional_Type_Name (Element_Info);
               begin
                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Append_Name & " (Value : in "
                     & Element_Type_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Tail : " & Root_Type & " := "
                     & Runtime_Name & ".From_Array ((1 => Value));",
                     2);
                  Append_Line
                    (Buffer,
                     "Updated : constant " & Root_Type & " := "
                     & Runtime_Name & ".Concat (State_Value, Tail);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Free_Value ("State_Value", Decl.Type_Info, 3);
                  Append_Free_Value ("Tail", Decl.Type_Info, 3);
                  Append_Line (Buffer, "State_Value := Updated;", 3);
                  Append_Line (Buffer, "end " & Shared_Append_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Pop_Last_Name & " (Result : out "
                     & Optional_Element_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := "
                     & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Line
                    (Buffer,
                     "Result := " & Optional_Default_Expr (Element_Info) & ";",
                     3);
                  Append_Line (Buffer, "if Length_Value = 0 then", 3);
                  Append_Line (Buffer, "return;", 4);
                  Append_Line (Buffer, "end if;", 3);
                  Append_Line (Buffer, "declare", 3);
                  Append_Line
                    (Buffer,
                     "Last_Value : " & Element_Type_Name & " := "
                     & Runtime_Name & ".Element (State_Value, Positive (Length_Value));",
                     4);
                  Append_Line (Buffer, "begin", 3);
                  if Has_Heap_Value_Type (Unit, Document, Element_Info) then
                     Append_Line (Buffer, "Result.present := True;", 4);
                     Append_Copy_Value ("Result.value", "Last_Value", Element_Info, 4);
                  else
                     Append_Line
                       (Buffer,
                        "Result := (present => True, value => Last_Value);",
                        4);
                  end if;
                  Append_Line
                    (Buffer,
                     Element_Free_Name & " (Last_Value);",
                     4);
                  Append_Line (Buffer, "end;", 3);
                  Append_Line (Buffer, "declare", 3);
                  Append_Line
                    (Buffer,
                     "Updated : constant " & Root_Type & " := "
                     & "(if Length_Value = 1 then " & Runtime_Name & ".Empty else "
                     & Runtime_Name & ".Slice (State_Value, 1, Length_Value - 1));",
                     4);
                  Append_Line (Buffer, "begin", 3);
                  Append_Free_Value ("State_Value", Decl.Type_Info, 4);
                  Append_Line (Buffer, "State_Value := Updated;", 4);
                  Append_Line (Buffer, "end;", 3);
                  Append_Line (Buffer, "end " & Shared_Pop_Last_Name & ";", 2);
                  Append_Line (Buffer);
               end;
            end if;
         end;
      else
         for Field of Base_Info.Fields loop
            declare
               Field_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
               Field_Type_Name : constant String :=
                 Render_Type_Name_From_Text
                   (Unit,
                    Document,
                    FT.To_String (Field.Type_Name),
                    State);
               Getter_Name : constant String := Shared_Field_Getter_Name (FT.To_String (Field.Name));
               Setter_Name : constant String := Shared_Field_Setter_Name (FT.To_String (Field.Name));
               Field_Image : constant String := FT.To_String (Field.Name);
            begin
               Append_Line
                 (Buffer,
                  "function " & Getter_Name & " return "
                  & Field_Type_Name & " is",
                  2);
               if Heap_Root then
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
               end if;
               if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                  Append_Line
                    (Buffer,
                     "Result : " & Field_Type_Name & " := "
                     & Default_Value_Expr (Unit, Document, Field_Info)
                     & ";",
                     2);
               end if;
               Append_Line (Buffer, "begin", 2);
               if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                  Append_Copy_Value
                    ("Result",
                     "State_Value." & Field_Image,
                     Field_Info,
                     3);
                  Append_Line (Buffer, "return Result;", 3);
               else
                  Append_Line (Buffer, "return State_Value." & Field_Image & ";", 3);
               end if;
               Append_Line (Buffer, "end " & Getter_Name & ";", 2);
               Append_Line (Buffer);
               Append_Line
                 (Buffer,
                  "procedure " & Setter_Name & " (Value : in "
                  & Field_Type_Name & ") is",
                  2);
               if Heap_Root then
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
               end if;
               Append_Line (Buffer, "begin", 2);
               if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                  Append_Free_Value ("State_Value." & Field_Image, Field_Info, 3);
                  Append_Copy_Value
                    ("State_Value." & Field_Image,
                     "Value",
                     Field_Info,
                     3);
               else
                  Append_Line (Buffer, "State_Value." & Field_Image & " := Value;", 3);
               end if;
               Append_Line (Buffer, "end " & Setter_Name & ";", 2);
               Append_Line (Buffer);
               if Is_Plain_String_Type (Unit, Document, Field_Info) then
                  State.Needs_Safe_String_RT := True;
                  Append_Line
                    (Buffer,
                     "procedure " & Setter_Name & " (Value : in String) is",
                     2);
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  Append_Line (Buffer, "begin", 2);
                  Append_Line
                    (Buffer,
                     Setter_Name & " (Safe_String_RT.From_Literal (Value));",
                     3);
                  Append_Line (Buffer, "end " & Setter_Name & ";", 2);
                  Append_Line (Buffer);
               end if;
            end;
         end loop;
         declare
            Empty_Path : FT.UString_Vectors.Vector;
         begin
            Append_Nested_Setter_Bodies (Decl.Type_Info, Empty_Path);
         end;
      end if;
      Append_Line
        (Buffer,
         "procedure Initialize (Value : in " & Root_Type & ") is",
         2);
      if Heap_Root then
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
      end if;
      Append_Line (Buffer, "begin", 2);
      if Heap_Root then
         Append_Free_Value ("State_Value", Decl.Type_Info, 3);
         if Is_Container_Root then
            Append_Copy_Value ("State_Value", "Value", Decl.Type_Info, 3);
         else
            Append_Line
              (Buffer,
               Shared_Copy_Helper_Name (Decl.Type_Info) & " (State_Value, Value);",
               3);
         end if;
      else
         Append_Line (Buffer, "State_Value := Value;", 3);
      end if;
      Append_Line (Buffer, "end Initialize;", 2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      if Heap_Root then
         Append_Local_Warning_Restore (Buffer, 1);
      end if;
      Append_Line (Buffer);
      if Is_Public_Shared then
         Append_Public_Helper_Bodies;
      end if;
   end Render_Shared_Object_Body;
   function Channel_Model_Has_Value_Name
     (Channel : CM.Resolved_Channel_Decl) return String is
   begin
      return FT.To_String (Channel.Name) & "_Model_Has_Value";
   end Channel_Model_Has_Value_Name;
   function Channel_Model_Length_Name
     (Channel : CM.Resolved_Channel_Decl) return String is
   begin
      return FT.To_String (Channel.Name) & "_Model_Length";
   end Channel_Model_Length_Name;
   function Channel_Uses_Sequential_Scalar_Ghost_Model
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl) return Boolean
   is
   begin
      return Channel.Capacity = 1
        and then
          (Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
           or else Is_Growable_Array_Type (Unit, Document, Channel.Element_Type))
        and then Unit.Tasks.Is_Empty
        and then Unit.Subprograms.Is_Empty
        and then not Statements_Have_Select (Unit.Statements);
   end Channel_Uses_Sequential_Scalar_Ghost_Model;
   function Select_Dispatcher_Type_Name (Name : String) return String is
   begin
      return Name & "_Type";
   end Select_Dispatcher_Type_Name;
   procedure Render_Select_Dispatcher_Spec
     (Buffer : in out SU.Unbounded_String;
      Name   : String) is
   begin
      Append_Line
        (Buffer,
         "protected type "
         & Select_Dispatcher_Type_Name (Name)
         & " with Priority => System.Any_Priority'Last is",
         1);
      Append_Line (Buffer, "procedure Reset;", 2);
      Append_Line (Buffer, "procedure Signal;", 2);
      Append_Line
        (Buffer,
         "procedure Signal_Delay (Event : in out Ada.Real_Time.Timing_Events.Timing_Event);",
         2);
      Append_Line (Buffer, "entry Await (Timed_Out : out Boolean);", 2);
      Append_Line (Buffer, "private", 1);
      Append_Line (Buffer, "Signaled : Boolean := False;", 2);
      Append_Line (Buffer, "Delay_Expired : Boolean := False;", 2);
      Append_Line
        (Buffer,
         "end " & Select_Dispatcher_Type_Name (Name) & ";",
         1);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Spec;
   procedure Render_Select_Dispatcher_Object_Decl
     (Buffer : in out SU.Unbounded_String;
      Name   : String) is
   begin
      Append_Line
        (Buffer,
         Name
         & " : " & Select_Dispatcher_Type_Name (Name)
         & ASCII.LF
         & Indentation (1)
         & "  with Part_Of => Safe_Select_Internal_State;",
         1);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Object_Decl;
   procedure Render_Select_Dispatcher_Body
     (Buffer : in out SU.Unbounded_String;
      Name   : String) is
   begin
      Append_Line
        (Buffer,
         "protected body " & Select_Dispatcher_Type_Name (Name) & " is",
         1);
      Append_Line (Buffer, "procedure Reset is", 2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Signaled := False;", 3);
      Append_Line (Buffer, "Delay_Expired := False;", 3);
      Append_Line (Buffer, "end Reset;", 2);
      Append_Line (Buffer);
      Append_Line (Buffer, "procedure Signal is", 2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Signaled := True;", 3);
      Append_Line (Buffer, "end Signal;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure Signal_Delay (Event : in out Ada.Real_Time.Timing_Events.Timing_Event) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "pragma Unreferenced (Event);", 3);
      Append_Line (Buffer, "Delay_Expired := True;", 3);
      Append_Line (Buffer, "end Signal_Delay;", 2);
      Append_Line (Buffer);
      Append_Line (Buffer, "entry Await (Timed_Out : out Boolean) when Signaled or Delay_Expired is", 2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Timed_Out := Delay_Expired;", 3);
      Append_Line (Buffer, "Signaled := False;", 3);
      Append_Line (Buffer, "Delay_Expired := False;", 3);
      Append_Line (Buffer, "end Await;", 2);
      Append_Line
        (Buffer,
         "end " & Select_Dispatcher_Type_Name (Name) & ";",
         1);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Body;
   procedure Render_Select_Dispatcher_Delay_Helpers
     (Buffer        : in out SU.Unbounded_String;
      Dispatcher    : String;
      Timer_Name    : String;
      Init_Helper   : String;
      Deadline_Helper : String;
      Arm_Helper    : String;
      Cancel_Helper : String;
      Depth         : Natural := 1)
   is
   begin
      Append_Line
        (Buffer,
         "procedure " & Init_Helper,
         Depth);
      Append_Line
        (Buffer,
         "  with Global => (Output => " & Timer_Name & "),"
         & ASCII.LF
         & Indentation (Depth)
         & "       Always_Terminates;",
         Depth);
      Append_Line
        (Buffer,
         "function " & Deadline_Helper
         & " (Start : in Ada.Real_Time.Time;"
         & " Delay_Span : in Ada.Real_Time.Time_Span)"
         & " return Ada.Real_Time.Time",
         Depth);
      Append_Line (Buffer, "  with Global => null;", Depth);
      Append_Line
        (Buffer,
         "procedure " & Arm_Helper & " (Deadline : in Ada.Real_Time.Time)",
         Depth);
      Append_Line
        (Buffer,
         "  with Global => (In_Out => ("
         & Dispatcher
         & ", "
         & Timer_Name
         & ")),"
         & ASCII.LF
         & Indentation (Depth)
         & "       Always_Terminates;",
         Depth);
      Append_Line
        (Buffer,
         "procedure " & Cancel_Helper & " (Cancelled : out Boolean)",
         Depth);
      Append_Line
        (Buffer,
         "  with Global => (In_Out => ("
         & Dispatcher
         & ", "
         & Timer_Name
         & ")),"
         & ASCII.LF
         & Indentation (Depth)
         & "       Always_Terminates;",
         Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "procedure " & Init_Helper,
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "Cancelled : Boolean;", Depth + 1);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "Ada.Real_Time.Timing_Events.Cancel_Handler"
         & " ("
         & Timer_Name
         & ", Cancelled);",
         Depth + 1);
      Append_Line (Buffer, "end " & Init_Helper & ";", Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "function " & Deadline_Helper
         & " (Start : in Ada.Real_Time.Time;"
         & " Delay_Span : in Ada.Real_Time.Time_Span)"
         & " return Ada.Real_Time.Time",
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "if Ada.Real_Time.""<="" (Delay_Span, Ada.Real_Time.Time_Span_Zero) then",
         Depth + 1);
      Append_Line (Buffer, "return Start;", Depth + 2);
      Append_Line (Buffer, "end if;", Depth + 1);
      Append_Line (Buffer, "begin", Depth + 1);
      Append_Line (Buffer, "return Start + Delay_Span;", Depth + 2);
      Append_Line (Buffer, "exception", Depth + 1);
      Append_Line (Buffer, "when others =>", Depth + 2);
      Append_Line (Buffer, "return Ada.Real_Time.Time_Last;", Depth + 3);
      Append_Line (Buffer, "end;", Depth + 1);
      Append_Line (Buffer, "end " & Deadline_Helper & ";", Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "procedure " & Arm_Helper & " (Deadline : in Ada.Real_Time.Time)",
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "Ada.Real_Time.Timing_Events.Set_Handler"
         & " ("
         & Timer_Name
         & ", Deadline, "
         & Dispatcher
         & ".Signal_Delay'Access);",
         Depth + 1);
      Append_Line (Buffer, "end " & Arm_Helper & ";", Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "procedure " & Cancel_Helper & " (Cancelled : out Boolean)",
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "Ada.Real_Time.Timing_Events.Cancel_Handler"
         & " ("
         & Timer_Name
         & ", Cancelled);",
         Depth + 1);
      Append_Line (Buffer, "end " & Cancel_Helper & ";", Depth);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Delay_Helpers;
   procedure Append_Select_Dispatcher_Signals
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Channel_Name : String;
      Depth        : Natural)
   is
      Dispatcher_Names : FT.UString_Vectors.Vector;
   begin
      Collect_Select_Dispatcher_Names_For_Channel
        (Unit.Statements,
         Channel_Name,
         Dispatcher_Names);
      for Task_Item of Unit.Tasks loop
         Collect_Select_Dispatcher_Names_For_Channel
           (Task_Item.Statements,
            Channel_Name,
            Dispatcher_Names);
      end loop;

      for Name of Dispatcher_Names loop
         Append_Line (Buffer, FT.To_String (Name) & ".Signal;", Depth);
      end loop;
   end Append_Select_Dispatcher_Signals;
   procedure Render_Channel_Generated_Value_Helpers
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Heap_Value    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Channel.Element_Type);
      Copy_Helper   : constant String := Name & "_Copy_Value";
      Free_Helper   : constant String := Name & "_Free_Value";
      Generated_Channel_Helpers : FT.UString_Vectors.Vector;
      Runtime_Dependency_Types  : FT.UString_Vectors.Vector;

      function Channel_Helper_Base_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Heap_Helper_Base_Name
             (AI.Heap_Helper_Channel, Name, Unit, Document, Info);
      end Channel_Helper_Base_Name;

      function Channel_Copy_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return Channel_Helper_Base_Name (Info) & "_Copy";
      end Channel_Copy_Helper_Name;

      function Channel_Free_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return Channel_Helper_Base_Name (Info) & "_Free";
      end Channel_Free_Helper_Name;

      procedure Render_Channel_Value_Helpers (Info : GM.Type_Descriptor);

      procedure Render_Channel_Value_Helpers (Info : GM.Type_Descriptor) is
         Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         Kind      : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Type_Key  : constant String := Render_Type_Name (Info);
         Type_Name : constant String := Render_Type_Name (Info);

         procedure Ensure_Helper (Name_Text : String) is
         begin
            if Name_Text'Length = 0 then
               return;
            end if;

            Render_Channel_Value_Helpers
              (Resolve_Type_Name (Unit, Document, Name_Text));
         end Ensure_Helper;
      begin
         if not Needs_Generated_Heap_Helper (Unit, Document, Info)
           or else Contains_Name (Generated_Channel_Helpers, Type_Key)
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

         Generated_Channel_Helpers.Append (FT.To_UString (Type_Key));

         Append_Line
           (Buffer,
            "procedure "
            & Channel_Copy_Helper_Name (Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Channel_Copy_Helper_Name (Info)
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
            AI.Heap_Helper_Channel,
            Name,
            Info,
            2);
         Append_Line (Buffer, "end " & Channel_Copy_Helper_Name (Info) & ";", 1);
         Append_Line (Buffer);

         Append_Local_Warning_Suppression (Buffer, 1);
         Append_Line
           (Buffer,
            "procedure "
            & Channel_Free_Helper_Name (Info)
            & " (Value : in out "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Channel_Free_Helper_Name (Info)
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
            AI.Heap_Helper_Channel,
            Name,
            Info,
            2);
         Append_Line
           (Buffer,
            "Value := " & Default_Value_Expr (Unit, Document, Info) & ";",
            2);
         Append_Line (Buffer, "end " & Channel_Free_Helper_Name (Info) & ";", 1);
         Append_Local_Warning_Restore (Buffer, 1);
         Append_Line (Buffer);
      end Render_Channel_Value_Helpers;
   begin
      if Heap_Value
        and then not Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
        and then not Is_Growable_Array_Type (Unit, Document, Channel.Element_Type)
      then
         Mark_Heap_Runtime_Dependencies
           (Unit,
            Document,
            Channel.Element_Type,
            State,
            Runtime_Dependency_Types);
         Render_Channel_Value_Helpers (Channel.Element_Type);

         Append_Line
           (Buffer,
            "procedure "
            & Copy_Helper
            & " (Target : out "
            & Element_Type
            & "; Source : "
            & Element_Type
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Copy_Helper
            & " (Target : out "
            & Element_Type
            & "; Source : "
            & Element_Type
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line
           (Buffer,
            Channel_Copy_Helper_Name (Channel.Element_Type)
            & " (Target, Source);",
            2);
         Append_Line (Buffer, "end " & Copy_Helper & ";", 1);
         Append_Line (Buffer);

         Append_Local_Warning_Suppression (Buffer, 1);
         Append_Line
           (Buffer,
            "procedure "
            & Free_Helper
            & " (Value : in out "
            & Element_Type
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Free_Helper
            & " (Value : in out "
            & Element_Type
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Heap_Free_Value
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Channel,
            Name,
            "Value",
            Channel.Element_Type,
            2);
         Append_Line (Buffer, "end " & Free_Helper & ";", 1);
         Append_Local_Warning_Restore (Buffer, 1);
         Append_Line (Buffer);
      end if;
   end Render_Channel_Generated_Value_Helpers;
   procedure Render_Channel_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      Bronze   : MB.Bronze_Result)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Capacity      : constant String := Trim_Image (Channel.Capacity);
      Type_Name     : constant String := Name & "_Channel";
      Length_Helper : constant String := Name & "_Element_Length";
      Well_Formed_Helper : constant String := Name & "_Well_Formed";
      Index_Subtype : constant String := Name & "_Index";
      Count_Subtype : constant String := Name & "_Count";
      Length_Buffer_Type : constant String := Name & "_Length_Buffer";
      Buffer_Type   : constant String := Name & "_Buffer";
      Stored_Length : constant String := "Stored_Length";
      Model_Has_Value : constant String := Channel_Model_Has_Value_Name (Channel);
      Model_Length : constant String := Channel_Model_Length_Name (Channel);
      Heap_Value    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Channel.Element_Type);
      Has_Length_Model : constant Boolean :=
        Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
        or else Is_Growable_Array_Type (Unit, Document, Channel.Element_Type);
      Single_Slot_Length_Model : constant Boolean :=
        Has_Length_Model and then Channel.Capacity = 1;
      Uses_Ghost_Scalar_Model : constant Boolean :=
        Channel_Uses_Sequential_Scalar_Ghost_Model
          (Unit, Document, Channel);
      --  The direct sequential single-slot string/growable path keeps the
      --  Value_Length formals even with the record-backed lowering so callers
      --  can carry the returned length directly through emitted proofs without
      --  relying on the protected-path receive-side equality bridge.
      Uses_Length_Formals : constant Boolean := Has_Length_Model;
      Uses_Runtime_Length_Buffer : constant Boolean :=
        Has_Length_Model and then not Uses_Ghost_Scalar_Model;
      Send_Mode     : constant String :=
        (if Heap_Value then "in out " else "in ");
      Receive_Mode  : constant String := "out ";
      Buffer_Default : constant String :=
        Default_Value_Expr (Unit, Document, Channel.Element_Type);
      Ghost_Send_Post : constant String :=
        Model_Has_Value
        & " and then "
        & Model_Length
        & " = Value_Length";
      Ghost_Model_Unchanged : constant String :=
        Model_Has_Value
        & " = "
        & Model_Has_Value
        & "'Old and then "
        & Model_Length
        & " = "
        & Model_Length
        & "'Old";
      Ghost_Receive_Post : constant String :=
        "Value_Length = "
        & Model_Length
        & "'Old and then (not "
        & Model_Has_Value
        & ") and then "
        & Model_Length
        & " = 0";
      Uses_Environment_Ceiling : constant Boolean :=
        Channel.Is_Public
        or else Channel_Uses_Environment_Task (Bronze, Name)
        or else Channel_Uses_Unspecified_Task_Priority (Unit, Bronze, Name);
      Ceiling       : Long_Long_Integer :=
        (if Channel.Has_Required_Ceiling then Channel.Required_Ceiling else 0);
   begin
      for Item of Bronze.Ceilings loop
         if FT.To_String (Item.Channel_Name) = Name then
            Ceiling := Item.Priority;
            exit;
         end if;
      end loop;
      if Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            "type " & Type_Name & " is record",
            1);
         Append_Line
           (Buffer,
            "Value : " & Element_Type & " := " & Buffer_Default & ";",
            2);
         Append_Line (Buffer, "Full : Boolean := False;", 2);
         Append_Line (Buffer, "Stored_Length_Value : Natural := 0;", 2);
         Append_Line (Buffer, "end record;", 1);
         Append_Line (Buffer, Name & " : " & Type_Name & ";", 1);
         if Has_Length_Model then
            Append_Line
              (Buffer,
               "function "
               & Length_Helper
               & " (Value : "
               & Element_Type
               & ") return Natural with Global => null;",
               1);
            Append_Line
              (Buffer,
               "function "
               & Well_Formed_Helper
               & " return Boolean is ((if "
               & Name
               & ".Full then "
               & Name
               & ".Stored_Length_Value = "
               & Length_Helper
               & " ("
               & Name
               & ".Value) else "
               & Name
               & ".Stored_Length_Value = 0)) with Global => (Input => "
               & Name
               & ");",
               1);
         end if;
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Send (Value : "
            & Send_Mode
            & Element_Type
            & "; Value_Length : in Natural)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & " and then not "
            & Name
            & ".Full and then Value_Length = "
            & Length_Helper
            & " (Value), Post => "
            & Well_Formed_Helper
            & " and then "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = Value_Length;",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Receive (Value : "
            & Receive_Mode
            & Element_Type
            & "; Value_Length : out Natural)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & " and then "
            & Name
            & ".Full, Post => "
            & Well_Formed_Helper
            & " and then Value_Length = "
            & Name
            & ".Stored_Length_Value'Old and then Value_Length = "
            & Length_Helper
            & " (Value) and then not "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = 0;",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Try_Send (Value : "
            & Send_Mode
            & Element_Type
            & "; Value_Length : in Natural; Success : out Boolean)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & " and then Value_Length = "
            & Length_Helper
            & " (Value), Post => "
            & Well_Formed_Helper
            & " and then (if Success then "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = Value_Length else "
            & Name
            & ".Full = "
            & Name
            & ".Full'Old and then "
            & Name
            & ".Stored_Length_Value = "
            & Name
            & ".Stored_Length_Value'Old);",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Try_Receive (Value : "
            & Receive_Mode
            & Element_Type
            & "; Value_Length : out Natural; Success : out Boolean)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & ", Post => "
            & Well_Formed_Helper
            & " and then (if Success then Value_Length = "
            & Name
            & ".Stored_Length_Value'Old and then Value_Length = "
            & Length_Helper
            & " (Value) and then not "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = 0 else Value_Length = 0 and then "
            & Name
            & ".Full = "
            & Name
            & ".Full'Old and then "
            & Name
            & ".Stored_Length_Value = "
            & Name
            & ".Stored_Length_Value'Old);",
            1);
         Append_Line (Buffer);
         return;
      end if;
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
      if Uses_Runtime_Length_Buffer then
         Append_Line
           (Buffer,
            "type " & Length_Buffer_Type & " is array (" & Index_Subtype & ") of Natural;",
            1);
      end if;
      if Has_Length_Model then
         Append_Line
           (Buffer,
            "function "
            & Length_Helper
            & " (Value : "
            & Element_Type
            & ") return Natural with Global => null;",
            1);
         if Uses_Ghost_Scalar_Model then
            Append_Initialization_Warning_Suppression (Buffer, 1);
            --  These model scalars intentionally remain ordinary runtime
            --  declarations. On the current GNAT/SPARK toolchain, marking
            --  them as Ghost makes the protected send/receive bodies reject
            --  the generated reads/writes as illegal Ghost use in non-Ghost
            --  contexts.
            Append_Line
              (Buffer,
               Model_Has_Value & " : Boolean := False;",
               1);
            Append_Line
              (Buffer,
               Model_Length & " : Natural := 0;",
               1);
            Append_Initialization_Warning_Restore (Buffer, 1);
         end if;
      end if;
      Append_Line
        (Buffer,
        "protected type "
        & Type_Name
        & " with Priority => "
        & (if Uses_Environment_Ceiling
           then "System.Any_Priority'Last"
           else Trim_Image (Ceiling))
        & " is",
        1);
      Append_Line
        (Buffer,
         "entry Send (Value : "
         & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & ")"
         & (if Uses_Ghost_Scalar_Model
            then " with Post => " & Ghost_Send_Post
            elsif Single_Slot_Length_Model
            then " with Post => " & Stored_Length & " = Value_Length"
            else "")
         & ";",
         2);
      Append_Line
        (Buffer,
         "entry Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & ")"
         & (if Uses_Ghost_Scalar_Model
            then " with Post => " & Ghost_Receive_Post
            elsif Single_Slot_Length_Model
            then
              " with Post => Value_Length = "
              & Stored_Length
              & "'Old and then "
              & Stored_Length
              & " = 0"
            else "")
         & ";",
         2);
      Append_Line
        (Buffer,
         "procedure Try_Send (Value : "
         & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & "; Success : out Boolean)"
         & (if Uses_Ghost_Scalar_Model
            then
              " with Post => (if Success then "
              & Ghost_Send_Post
              & " else "
              & Ghost_Model_Unchanged
              & ")"
            else "")
         & ";",
         2);
      Append_Line
        (Buffer,
         "procedure Try_Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & "; Success : out Boolean)"
         & (if Uses_Ghost_Scalar_Model
            then
              " with Post => (if Success then "
              & Ghost_Receive_Post
              & " else "
              & Ghost_Model_Unchanged
              & " and then Value_Length = 0)"
            else "")
         & ";",
         2);
      if Single_Slot_Length_Model and then not Uses_Ghost_Scalar_Model then
         --  Keep the Stored_Length fallback for single-slot channels that do
         --  not qualify for the sequential Ghost-model path, such as the
         --  broader tasking/subprogram channel surface.
         Append_Line (Buffer, "function " & Stored_Length & " return Natural;", 2);
      end if;
      Append_Line (Buffer, "private", 1);
      Append_Line
         (Buffer,
          "Buffer : "
          & Buffer_Type
          & " := (others => "
          & Default_Value_Expr (Unit, Document, Channel.Element_Type)
          & ");",
          2);
      if Uses_Runtime_Length_Buffer then
         Append_Line
           (Buffer,
            "Lengths : " & Length_Buffer_Type & " := (others => 0);",
            2);
      end if;
      Append_Line (Buffer, "Head   : " & Index_Subtype & " := " & Index_Subtype & "'First;", 2);
      Append_Line (Buffer, "Tail   : " & Index_Subtype & " := " & Index_Subtype & "'First;", 2);
      Append_Line (Buffer, "Count  : " & Count_Subtype & " := 0;", 2);
      if Single_Slot_Length_Model and then not Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, "Stored_Length_Value : Natural := 0;", 2);
      end if;
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer, Name & " : " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Channel_Spec;
   procedure Render_Channel_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Capacity      : constant String := Trim_Image (Channel.Capacity);
      Type_Name     : constant String := Name & "_Channel";
      Length_Helper : constant String := Name & "_Element_Length";
      Index_Subtype : constant String := Name & "_Index";
      Stored_Length : constant String := "Stored_Length";
      Model_Has_Value : constant String := Channel_Model_Has_Value_Name (Channel);
      Model_Length : constant String := Channel_Model_Length_Name (Channel);
      Heap_Value    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Channel.Element_Type);
      Has_Length_Model : constant Boolean :=
        Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
        or else Is_Growable_Array_Type (Unit, Document, Channel.Element_Type);
      Single_Slot_Length_Model : constant Boolean :=
        Has_Length_Model and then Channel.Capacity = 1;
      Uses_Ghost_Scalar_Model : constant Boolean :=
        Channel_Uses_Sequential_Scalar_Ghost_Model
          (Unit, Document, Channel);
      --  See the matching note in Render_Channel_Spec: the Ghost-model path
      --  still carries Value_Length until the remaining receive-side bridge
      --  can be removed without reopening the proof lane.
      Uses_Length_Formals : constant Boolean := Has_Length_Model;
      Uses_Runtime_Length_Buffer : constant Boolean :=
        Has_Length_Model and then not Uses_Ghost_Scalar_Model;
      Send_Mode     : constant String :=
        (if Heap_Value then "in out " else "in ");
      Receive_Mode  : constant String := "out ";
      Buffer_Default : constant String :=
        Default_Value_Expr (Unit, Document, Channel.Element_Type);
   begin
      Render_Channel_Generated_Value_Helpers
        (Buffer, Unit, Document, Channel, State);

      if Has_Length_Model then
         Append_Line
           (Buffer,
            "function "
            & Length_Helper
            & " (Value : "
            & Element_Type
            & ") return Natural is ("
            & (if Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
               then "Safe_String_RT.Length (Value)"
               else
                 Array_Runtime_Instance_Name
                   (Base_Type (Unit, Document, Channel.Element_Type))
                 & ".Length (Value)")
            & ");",
            1);
         Append_Line (Buffer);
      end if;

      if Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            "procedure " & Name & "_Send (Value : " & Send_Mode & Element_Type & "; Value_Length : in Natural) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, Name & ".Value := Value;", 2);
         Append_Line (Buffer, Name & ".Full := True;", 2);
         Append_Line (Buffer, Name & ".Stored_Length_Value := Value_Length;", 2);
         Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 2);
         if Heap_Value then
            Append_Line (Buffer, "Value := " & Buffer_Default & ";", 2);
         end if;
         Append_Line (Buffer, "end " & Name & "_Send;", 1);
         Append_Line (Buffer);
         Append_Line
           (Buffer,
            "procedure " & Name & "_Receive (Value : " & Receive_Mode & Element_Type & "; Value_Length : out Natural) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "Value := " & Name & ".Value;", 2);
         Append_Line (Buffer, "Value_Length := " & Name & ".Stored_Length_Value;", 2);
         Append_Line (Buffer, Name & ".Value := " & Buffer_Default & ";", 2);
         Append_Line (Buffer, Name & ".Full := False;", 2);
         Append_Line (Buffer, Name & ".Stored_Length_Value := 0;", 2);
         Append_Line (Buffer, "end " & Name & "_Receive;", 1);
         Append_Line (Buffer);
         Append_Line
           (Buffer,
            "procedure " & Name & "_Try_Send (Value : " & Send_Mode & Element_Type & "; Value_Length : in Natural; Success : out Boolean) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "if not " & Name & ".Full then", 2);
         Append_Line (Buffer, Name & ".Value := Value;", 3);
         Append_Line (Buffer, Name & ".Full := True;", 3);
         Append_Line (Buffer, Name & ".Stored_Length_Value := Value_Length;", 3);
         Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 3);
         if Heap_Value then
            Append_Line (Buffer, "Value := " & Buffer_Default & ";", 3);
         end if;
         Append_Line (Buffer, "Success := True;", 3);
         Append_Line (Buffer, "else", 2);
         Append_Line (Buffer, "Success := False;", 3);
         Append_Line (Buffer, "end if;", 2);
         Append_Line (Buffer, "end " & Name & "_Try_Send;", 1);
         Append_Line (Buffer);
         Append_Line
           (Buffer,
            "procedure " & Name & "_Try_Receive (Value : " & Receive_Mode & Element_Type & "; Value_Length : out Natural; Success : out Boolean) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "if " & Name & ".Full then", 2);
         Append_Line (Buffer, "Value := " & Name & ".Value;", 3);
         Append_Line (Buffer, "Value_Length := " & Name & ".Stored_Length_Value;", 3);
         Append_Line (Buffer, Name & ".Value := " & Buffer_Default & ";", 3);
         Append_Line (Buffer, Name & ".Full := False;", 3);
         Append_Line (Buffer, Name & ".Stored_Length_Value := 0;", 3);
         Append_Line (Buffer, "Success := True;", 3);
         Append_Line (Buffer, "else", 2);
         Append_Line (Buffer, "Value := " & Buffer_Default & ";", 3);
         Append_Line (Buffer, "Value_Length := 0;", 3);
         Append_Line (Buffer, "Success := False;", 3);
         Append_Line (Buffer, "end if;", 2);
         Append_Line (Buffer, "end " & Name & "_Try_Receive;", 1);
         Append_Line (Buffer);
         return;
      end if;

      Append_Line (Buffer, "protected body " & Type_Name & " is", 1);
      if Single_Slot_Length_Model and then not Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            "function " & Stored_Length & " return Natural is (Stored_Length_Value);",
            2);
         Append_Line (Buffer);
      end if;
      Append_Line
        (Buffer,
         "entry Send (Value : "
         & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & ")",
         2);
      Append_Line
        (Buffer,
         "when Count < "
         & Capacity
         & " is",
         3);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Buffer (Tail) := Value;", 3);
      if Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            Model_Has_Value & " := True;",
            3);
         Append_Line
           (Buffer,
            Model_Length & " := Value_Length;",
            3);
      elsif Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Tail) := Value_Length;", 3);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := Value_Length;", 3);
         end if;
      end if;
      if Heap_Value then
         Append_Line (Buffer, "Value := " & Buffer_Default & ";", 3);
      end if;
      Append_Line (Buffer, "if Tail = " & Index_Subtype & "'Last then", 3);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'First;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'Succ (Tail);", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "Count := Count + 1;", 3);
      Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 3);
      Append_Line (Buffer, "end Send;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "entry Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & ")",
         2);
      Append_Line
        (Buffer,
         "when Count > 0"
         & " is",
         3);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Value := Buffer (Head);", 3);
      if Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, "Value_Length := " & Model_Length & ";", 3);
         Append_Line (Buffer, Model_Has_Value & " := False;", 3);
         Append_Line (Buffer, Model_Length & " := 0;", 3);
      elsif Uses_Runtime_Length_Buffer then
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Value_Length := Stored_Length_Value;", 3);
         else
            Append_Line (Buffer, "Value_Length := Lengths (Head);", 3);
         end if;
      end if;
      Append_Line (Buffer, "Buffer (Head) := " & Buffer_Default & ";", 3);
      if Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Head) := 0;", 3);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := 0;", 3);
         end if;
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
         "procedure Try_Send (Value : " & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & "; Success : out Boolean) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line
        (Buffer,
        "if Count < "
         & Capacity
         & " then",
         3);
      Append_Line (Buffer, "Buffer (Tail) := Value;", 4);
      if Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, Model_Has_Value & " := True;", 4);
         Append_Line
           (Buffer,
            Model_Length & " := Value_Length;",
            4);
      elsif Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Tail) := Value_Length;", 4);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := Value_Length;", 4);
         end if;
      end if;
      if Heap_Value then
         Append_Line (Buffer, "Value := " & Buffer_Default & ";", 4);
      end if;
      Append_Line (Buffer, "if Tail = " & Index_Subtype & "'Last then", 4);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'First;", 5);
      Append_Line (Buffer, "else", 4);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'Succ (Tail);", 5);
      Append_Line (Buffer, "end if;", 4);
      Append_Line (Buffer, "Count := Count + 1;", 4);
      Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 4);
      Append_Line (Buffer, "Success := True;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Success := False;", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "end Try_Send;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure Try_Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & "; Success : out Boolean) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "if Count > 0 then", 3);
      Append_Line (Buffer, "Value := Buffer (Head);", 4);
      if Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, "Value_Length := " & Model_Length & ";", 4);
         Append_Line (Buffer, Model_Has_Value & " := False;", 4);
         Append_Line (Buffer, Model_Length & " := 0;", 4);
      elsif Uses_Runtime_Length_Buffer then
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Value_Length := Stored_Length_Value;", 4);
         else
            Append_Line (Buffer, "Value_Length := Lengths (Head);", 4);
         end if;
      end if;
      Append_Line (Buffer, "Buffer (Head) := " & Buffer_Default & ";", 4);
      if Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Head) := 0;", 4);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := 0;", 4);
         end if;
      end if;
      Append_Line (Buffer, "if Head = " & Index_Subtype & "'Last then", 4);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'First;", 5);
      Append_Line (Buffer, "else", 4);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'Succ (Head);", 5);
      Append_Line (Buffer, "end if;", 4);
      Append_Line (Buffer, "Count := Count - 1;", 4);
      Append_Line (Buffer, "Success := True;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Value := " & Buffer_Default & ";", 4);
      if Uses_Length_Formals then
         Append_Line (Buffer, "Value_Length := 0;", 4);
      end if;
      Append_Line (Buffer, "Success := False;", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "end Try_Receive;", 2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Channel_Body;
end Safe_Frontend.Ada_Emit.Channels;
