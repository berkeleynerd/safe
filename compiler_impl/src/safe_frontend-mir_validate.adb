with Ada.Containers.Indefinite_Vectors;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNATCOLL.JSON;
with Safe_Frontend.Mir_Json;
with Safe_Frontend.Types;

package body Safe_Frontend.Mir_Validate is
   package FT renames Safe_Frontend.Types;
   package GM renames Safe_Frontend.Mir_Model;
   package US renames Ada.Strings.Unbounded;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   use type String_Vectors.Vector;
   use type GM.Mir_Format_Kind;

   Validation_Error : exception;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Validation_Error with Message;
      end if;
   end Require;

   function Image (Item : Natural) return String is
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (Item), Ada.Strings.Both);
   end Image;

   function Is_Terminator_Kind (Kind : String) return Boolean is
   begin
      return Kind = "jump" or else Kind = "branch" or else Kind = "return";
   end Is_Terminator_Kind;

   function Is_Forbidden_Op (Kind : String) return Boolean is
   begin
      return Kind = "if" or else Kind = "while" or else Kind = "for";
   end Is_Forbidden_Op;

   function Is_Ownership_Effect (Kind : String) return Boolean is
   begin
      return
        Kind = "Move"
        or else Kind = "Borrow"
        or else Kind = "Observe"
        or else Kind = "None";
   end Is_Ownership_Effect;

   function Contains
     (Items : String_Vectors.Vector;
      Value : String) return Boolean
   is
   begin
      for Item of Items loop
         if Item = Value then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Render (Items : String_Vectors.Vector) return String is
      Result : US.Unbounded_String := US.To_Unbounded_String ("[");
   begin
      if not Items.Is_Empty then
         for Index in Items.First_Index .. Items.Last_Index loop
            if Index > Items.First_Index then
               US.Append (Result, ", ");
            end if;
            US.Append (Result, Items (Index));
         end loop;
      end if;
      US.Append (Result, "]");
      return US.To_String (Result);
   end Render;

   function Value_At
     (Array_Value : GNATCOLL.JSON.JSON_Array;
      Index       : Positive) return GNATCOLL.JSON.JSON_Value
   is
      use GNATCOLL.JSON;
   begin
      return Get (Array_Value, Index);
   end Value_At;

   function Field_Value
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Value
   is
      use GNATCOLL.JSON;
   begin
      return Get (Object_Value, Field);
   end Field_Value;

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

   function Is_Operand_Dict (Value : GNATCOLL.JSON.JSON_Value) return Boolean is
      use GNATCOLL.JSON;
   begin
      return
        Value.Kind = JSON_Object_Type
        and then Has_Field (Value, "kind")
        and then Has_Field (Value, "span");
   end Is_Operand_Dict;

   procedure Validate_Span
     (Value : GNATCOLL.JSON.JSON_Value;
      Where : String);

   procedure Validate_Operand
     (Value : GNATCOLL.JSON.JSON_Value;
      Where : String);

   function Json_Array_Field
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      Where        : String) return GNATCOLL.JSON.JSON_Array;

   procedure Validate_Block
     (Block     : GNATCOLL.JSON.JSON_Value;
      Valid_Ids : String_Vectors.Vector;
      Where     : String);

   procedure Validate_Scope
     (Scope           : GNATCOLL.JSON.JSON_Value;
      Valid_Scope_Ids : String_Vectors.Vector;
      Valid_Local_Ids : String_Vectors.Vector;
      Valid_Block_Ids : String_Vectors.Vector;
      Where           : String);

   procedure Validate_Graph_V2
     (Graph       : GNATCOLL.JSON.JSON_Value;
      Graph_Index : Positive);

   procedure Validate_Graph
     (Graph       : GNATCOLL.JSON.JSON_Value;
      Graph_Index : Positive;
      Format      : GM.Mir_Format_Kind);

   procedure Validate_Span
     (Value : GNATCOLL.JSON.JSON_Value;
      Where : String)
   is
      use GNATCOLL.JSON;
   begin
      Require (Value.Kind = JSON_Object_Type, Where & ": span must be an object");
      Require
        (Has_Field (Value, "start_line")
         and then Field_Value (Value, "start_line").Kind = JSON_Int_Type,
         Where & ": missing start_line");
      Require
        (Has_Field (Value, "start_col")
         and then Field_Value (Value, "start_col").Kind = JSON_Int_Type,
         Where & ": missing start_col");
      Require
        (Has_Field (Value, "end_line")
         and then Field_Value (Value, "end_line").Kind = JSON_Int_Type,
         Where & ": missing end_line");
      Require
        (Has_Field (Value, "end_col")
         and then Field_Value (Value, "end_col").Kind = JSON_Int_Type,
         Where & ": missing end_col");
   end Validate_Span;

   procedure Validate_Operand
     (Value : GNATCOLL.JSON.JSON_Value;
      Where : String)
   is
      use GNATCOLL.JSON;
      Child : JSON_Value;
   begin
      Require (Value.Kind = JSON_Object_Type, Where & ": operand must be an object");
      Validate_Span (Field_Or_Null (Value, "span"), Where & ".span");

      Require
        (Has_Field (Value, "kind")
         and then Field_Value (Value, "kind").Kind = JSON_String_Type,
         Where & ": missing operand kind");

      declare
         Kind : constant String := Get (Field_Value (Value, "kind"));
      begin
         if Kind /= "scope_enter" and then Kind /= "scope_exit" then
            Require
              (Has_Field (Value, "type")
               and then Field_Value (Value, "type").Kind = JSON_String_Type,
               Where & ": missing operand type");
         end if;

         if Is_Forbidden_Op (Kind) then
            raise Validation_Error with Where & ": forbidden high-level MIR op " & Kind;
         end if;
      end;

      if Has_Field (Value, "op")
        and then Field_Value (Value, "op").Kind = JSON_String_Type
        and then Get (Field_Value (Value, "op")) = "and then"
      then
         raise Validation_Error
           with Where & ": `and then` must lower into CFG, not remain in MIR operands";
      end if;

      declare
         procedure Validate_Child (Key : String) is
         begin
            if Has_Field (Value, Key) then
               Child := Field_Value (Value, Key);
               if Is_Operand_Dict (Child) then
                  Validate_Operand (Child, Where & "." & Key);
               end if;
            end if;
         end Validate_Child;

         procedure Validate_List (Key : String) is
         begin
            if Has_Field (Value, Key)
              and then Field_Value (Value, Key).Kind = JSON_Array_Type
            then
               declare
                  Items : constant JSON_Array := Get (Field_Value (Value, Key));
               begin
                  for Index in 1 .. Length (Items) loop
                     Child := Value_At (Items, Index);
                     if Child.Kind = JSON_Object_Type and then Has_Field (Child, "expr") then
                        Validate_Span
                          (Field_Or_Null (Child, "span"),
                           Where & "." & Key & "[" & Image (Index - 1) & "].span");
                        Validate_Operand
                          (Field_Value (Child, "expr"),
                           Where & "." & Key & "[" & Image (Index - 1) & "].expr");
                     elsif Is_Operand_Dict (Child) then
                        Validate_Operand
                          (Child,
                           Where & "." & Key & "[" & Image (Index - 1) & "]");
                     end if;
                  end loop;
               end;
            end if;
         end Validate_List;
      begin
         Validate_Child ("left");
         Validate_Child ("right");
         Validate_Child ("expr");
         Validate_Child ("prefix");
         Validate_Child ("callee");
         Validate_Child ("target");
         Validate_Child ("value");
         Validate_Child ("condition");

         Validate_List ("indices");
         Validate_List ("args");
         Validate_List ("fields");
      end;
   end Validate_Operand;

   function Json_Array_Field
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String;
      Where        : String) return GNATCOLL.JSON.JSON_Array
   is
      use GNATCOLL.JSON;
      Prefix : constant String :=
        (if Where = "" then "" else Where & ": ");
   begin
      Require
        (Object_Value.Kind = JSON_Object_Type
         and then Has_Field (Object_Value, Field)
         and then Field_Value (Object_Value, Field).Kind = JSON_Array_Type,
         Prefix & Field & " must be a list");
      return Get (Field_Value (Object_Value, Field));
   end Json_Array_Field;

   procedure Validate_Block
     (Block     : GNATCOLL.JSON.JSON_Value;
      Valid_Ids : String_Vectors.Vector;
      Where     : String)
   is
      use GNATCOLL.JSON;
      Ops        : JSON_Array;
      Terminator : JSON_Value;
   begin
      Require (Block.Kind = JSON_Object_Type, Where & ": block must be an object");
      Require
        (Has_Field (Block, "id")
         and then Field_Value (Block, "id").Kind = JSON_String_Type,
         Where & ": missing block id");
      Validate_Span (Field_Or_Null (Block, "span"), Where & ".span");

      Ops := Json_Array_Field (Block, "ops", Where);
      for Index in 1 .. Length (Ops) loop
         declare
            Op       : constant JSON_Value := Value_At (Ops, Index);
            Op_Where : constant String := Where & ".ops[" & Image (Index - 1) & "]";
         begin
            Require (Op.Kind = JSON_Object_Type, Op_Where & ": op must be an object");
            Require
              (Has_Field (Op, "kind")
               and then Field_Value (Op, "kind").Kind = JSON_String_Type,
               Op_Where & ": missing kind");

            declare
               Kind : constant String := Get (Field_Value (Op, "kind"));
               procedure Validate_Op_Operand (Key : String) is
               begin
                  if Has_Field (Op, Key) then
                     declare
                        Child : constant JSON_Value := Field_Value (Op, Key);
                     begin
                        if Is_Operand_Dict (Child) then
                           Validate_Operand (Child, Op_Where & "." & Key);
                        end if;
                     end;
                  end if;
               end Validate_Op_Operand;
            begin
               if Is_Forbidden_Op (Kind) then
                  raise Validation_Error
                    with Op_Where & ": high-level control op `" & Kind & "` leaked into MIR";
               end if;

               Validate_Span (Field_Or_Null (Op, "span"), Op_Where & ".span");
               Validate_Op_Operand ("target");
               Validate_Op_Operand ("value");
            end;
         end;
      end loop;

      Require
        (Has_Field (Block, "terminator")
         and then Field_Value (Block, "terminator").Kind = JSON_Object_Type,
         Where & ": every block must have a terminator");
      Terminator := Field_Value (Block, "terminator");
      Require
        (Has_Field (Terminator, "kind")
         and then Field_Value (Terminator, "kind").Kind = JSON_String_Type,
         Where & ": invalid terminator kind <missing>");

      declare
         Kind : constant String := Get (Field_Value (Terminator, "kind"));
      begin
         Require
           (Is_Terminator_Kind (Kind),
            Where & ": invalid terminator kind " & Kind);
         Validate_Span (Field_Or_Null (Terminator, "span"), Where & ".terminator.span");

         if Kind = "jump" then
            Require
              (Has_Field (Terminator, "target")
               and then Field_Value (Terminator, "target").Kind = JSON_String_Type
               and then Contains (Valid_Ids, Get (Field_Value (Terminator, "target"))),
               Where & ": jump target missing or invalid");
         elsif Kind = "branch" then
            Require
              (Has_Field (Terminator, "true_target")
               and then Field_Value (Terminator, "true_target").Kind = JSON_String_Type
               and then Contains
                 (Valid_Ids, Get (Field_Value (Terminator, "true_target"))),
               Where & ": branch true_target missing or invalid");
            Require
              (Has_Field (Terminator, "false_target")
               and then Field_Value (Terminator, "false_target").Kind = JSON_String_Type
               and then Contains
                 (Valid_Ids, Get (Field_Value (Terminator, "false_target"))),
               Where & ": branch false_target missing or invalid");
            Validate_Operand
              (Field_Or_Null (Terminator, "condition"),
               Where & ".terminator.condition");
         elsif Has_Field (Terminator, "value")
           and then Field_Value (Terminator, "value").Kind /= JSON_Null_Type
         then
            Validate_Operand
              (Field_Value (Terminator, "value"),
               Where & ".terminator.value");
         end if;
      end;
   end Validate_Block;

   procedure Validate_Scope
     (Scope           : GNATCOLL.JSON.JSON_Value;
      Valid_Scope_Ids : String_Vectors.Vector;
      Valid_Local_Ids : String_Vectors.Vector;
      Valid_Block_Ids : String_Vectors.Vector;
      Where           : String)
   is
      use GNATCOLL.JSON;
      Parent        : JSON_Value;
      Local_Ids     : JSON_Array;
      Exit_Blocks   : JSON_Array;
      Entry_Block   : JSON_Value;
      Parent_Valid  : Boolean;
      Entry_Valid   : Boolean;
   begin
      Require (Scope.Kind = JSON_Object_Type, Where & ": scope must be an object");
      Require
        (Has_Field (Scope, "id")
         and then Field_Value (Scope, "id").Kind = JSON_String_Type,
         Where & ": missing scope id");

      Parent := Field_Or_Null (Scope, "parent_scope_id");
      Parent_Valid :=
        Parent.Kind = JSON_Null_Type
        or else
          (Parent.Kind = JSON_String_Type
           and then Contains (Valid_Scope_Ids, Get (Parent)));
      Require
        (Parent_Valid,
        Where & ": invalid parent_scope_id");

      Require
        (Has_Field (Scope, "kind")
         and then Field_Value (Scope, "kind").Kind = JSON_String_Type,
         Where & ": missing scope kind");

      Local_Ids := Json_Array_Field (Scope, "local_ids", Where);
      for Index in 1 .. Length (Local_Ids) loop
         declare
            Local_Id : constant JSON_Value := Value_At (Local_Ids, Index);
         begin
            Require
              (Local_Id.Kind = JSON_String_Type
               and then Contains (Valid_Local_Ids, Get (Local_Id)),
               Where & ".local_ids[" & Image (Index - 1) & "]: invalid local id");
         end;
      end loop;

      Entry_Block := Field_Or_Null (Scope, "entry_block");
      Entry_Valid :=
        Entry_Block.Kind = JSON_String_Type
        and then
          (Get (Entry_Block) = ""
           or else Contains (Valid_Block_Ids, Get (Entry_Block)));
      Require
        (Entry_Valid,
        Where & ": invalid entry_block");

      Exit_Blocks := Json_Array_Field (Scope, "exit_blocks", Where);
      for Index in 1 .. Length (Exit_Blocks) loop
         declare
            Block_Id : constant JSON_Value := Value_At (Exit_Blocks, Index);
         begin
            Require
              (Block_Id.Kind = JSON_String_Type
               and then Contains (Valid_Block_Ids, Get (Block_Id)),
               Where & ".exit_blocks[" & Image (Index - 1) & "]: invalid block id");
         end;
      end loop;
   end Validate_Scope;

   procedure Validate_Graph_V2
     (Graph       : GNATCOLL.JSON.JSON_Value;
      Graph_Index : Positive)
   is
      use GNATCOLL.JSON;
      Where           : constant String := "graphs[" & Image (Graph_Index - 1) & "]";
      Scopes          : JSON_Array;
      Locals          : JSON_Array;
      Blocks          : JSON_Array;
      Valid_Scope_Ids : String_Vectors.Vector;
      Valid_Local_Ids : String_Vectors.Vector;
      Valid_Block_Ids : String_Vectors.Vector;
   begin
      Scopes := Json_Array_Field (Graph, "scopes", Where);
      Locals := Json_Array_Field (Graph, "locals", Where);
      Blocks := Json_Array_Field (Graph, "blocks", Where);
      Require
        (Length (Scopes) > 0,
         Where & ": mir-v2 graphs must have a non-empty scopes list");

      for Index in 1 .. Length (Scopes) loop
         declare
            Scope : constant JSON_Value := Value_At (Scopes, Index);
         begin
            if Scope.Kind = JSON_Object_Type
              and then Has_Field (Scope, "id")
              and then Field_Value (Scope, "id").Kind = JSON_String_Type
            then
               Valid_Scope_Ids.Append
                 (New_Item => Get (Field_Value (Scope, "id")),
                  Count    => 1);
            end if;
         end;
      end loop;

      for Index in 1 .. Length (Locals) loop
         declare
            Local : constant JSON_Value := Value_At (Locals, Index);
         begin
            if Local.Kind = JSON_Object_Type
              and then Has_Field (Local, "id")
              and then Field_Value (Local, "id").Kind = JSON_String_Type
            then
               Valid_Local_Ids.Append
                 (New_Item => Get (Field_Value (Local, "id")),
                  Count    => 1);
            end if;
         end;
      end loop;

      for Index in 1 .. Length (Blocks) loop
         declare
            Block : constant JSON_Value := Value_At (Blocks, Index);
         begin
            if Block.Kind = JSON_Object_Type
              and then Has_Field (Block, "id")
              and then Field_Value (Block, "id").Kind = JSON_String_Type
            then
               Valid_Block_Ids.Append
                 (New_Item => Get (Field_Value (Block, "id")),
                  Count    => 1);
            end if;
         end;
      end loop;

      for Index in 1 .. Length (Locals) loop
         declare
            Local       : constant JSON_Value := Value_At (Locals, Index);
            Local_Where : constant String := Where & ".locals[" & Image (Index - 1) & "]";
         begin
            Require
              (Has_Field (Local, "scope_id")
               and then Field_Value (Local, "scope_id").Kind = JSON_String_Type,
               Local_Where & ": mir-v2 locals must have scope_id");
            Require
              (Contains (Valid_Scope_Ids, Get (Field_Value (Local, "scope_id"))),
               Local_Where & ": unknown scope_id");
         end;
      end loop;

      for Index in 1 .. Length (Scopes) loop
         Validate_Scope
           (Value_At (Scopes, Index),
            Valid_Scope_Ids,
            Valid_Local_Ids,
            Valid_Block_Ids,
            Where & ".scopes[" & Image (Index - 1) & "]");
      end loop;

      for Block_Index in 1 .. Length (Blocks) loop
         declare
            Block       : constant JSON_Value := Value_At (Blocks, Block_Index);
            Block_Where : constant String := Where & ".blocks[" & Image (Block_Index - 1) & "]";
            Ops         : constant JSON_Array := Json_Array_Field (Block, "ops", Block_Where);
            Terminator  : constant JSON_Value := Field_Or_Null (Block, "terminator");
         begin
            Require
              (Has_Field (Block, "active_scope_id")
               and then Field_Value (Block, "active_scope_id").Kind = JSON_String_Type,
               Block_Where & ": mir-v2 blocks must have active_scope_id");
            Require
              (Contains (Valid_Scope_Ids, Get (Field_Value (Block, "active_scope_id"))),
               Block_Where & ": invalid active_scope_id");

            for Op_Index in 1 .. Length (Ops) loop
               declare
                  Op       : constant JSON_Value := Value_At (Ops, Op_Index);
                  Op_Where : constant String := Block_Where & ".ops[" & Image (Op_Index - 1) & "]";
               begin
                  if Op.Kind = JSON_Object_Type
                    and then Has_Field (Op, "kind")
                    and then Field_Value (Op, "kind").Kind = JSON_String_Type
                  then
                     declare
                        Kind : constant String := Get (Field_Value (Op, "kind"));
                     begin
                        if Kind = "assign" or else Kind = "call" then
                           Require
                             (Has_Field (Op, "ownership_effect")
                              and then Field_Value (Op, "ownership_effect").Kind = JSON_String_Type
                              and then Is_Ownership_Effect (Get (Field_Value (Op, "ownership_effect"))),
                              Op_Where & ": invalid ownership_effect");
                           Require
                             (Has_Field (Op, "type")
                              and then Field_Value (Op, "type").Kind = JSON_String_Type,
                              Op_Where & ": missing op type");
                        end if;
                        if Kind = "assign" then
                           Require
                             (Has_Field (Op, "declaration_init")
                              and then Field_Value (Op, "declaration_init").Kind = JSON_Boolean_Type,
                              Op_Where & ": assign missing declaration_init");
                        end if;
                        if Kind = "scope_enter" or else Kind = "scope_exit" then
                           Require
                             (Has_Field (Op, "scope_id")
                              and then Field_Value (Op, "scope_id").Kind = JSON_String_Type,
                              Op_Where & ": " & Kind & " missing scope_id");
                           Require
                             (Contains (Valid_Scope_Ids, Get (Field_Value (Op, "scope_id"))),
                              Op_Where & ": invalid scope_id");
                        end if;
                     end;
                  end if;
               end;
            end loop;

            Require
              (Has_Field (Terminator, "span")
               and then Field_Value (Terminator, "span").Kind = JSON_Object_Type,
               Block_Where & ".terminator: missing span");
            if Has_Field (Terminator, "kind")
              and then Field_Value (Terminator, "kind").Kind = JSON_String_Type
              and then Get (Field_Value (Terminator, "kind")) = "return"
            then
               Require
                 (Has_Field (Terminator, "ownership_effect")
                  and then Field_Value (Terminator, "ownership_effect").Kind = JSON_String_Type
                  and then Is_Ownership_Effect (Get (Field_Value (Terminator, "ownership_effect"))),
                  Block_Where & ".terminator: invalid ownership_effect");
            end if;
         end;
      end loop;
   end Validate_Graph_V2;

   procedure Validate_Graph
     (Graph       : GNATCOLL.JSON.JSON_Value;
      Graph_Index : Positive;
      Format      : GM.Mir_Format_Kind)
   is
      use GNATCOLL.JSON;
      Where        : constant String := "graphs[" & Image (Graph_Index - 1) & "]";
      Locals       : JSON_Array;
      Blocks       : JSON_Array;
      Actual_Ids   : String_Vectors.Vector;
      Expected_Ids : String_Vectors.Vector;
   begin
      Require (Graph.Kind = JSON_Object_Type, Where & ": graph must be an object");
      Require
        (Has_Field (Graph, "name")
         and then Field_Value (Graph, "name").Kind = JSON_String_Type,
         Where & ": missing graph name");

      Locals := Json_Array_Field (Graph, "locals", Where);
      Blocks := Json_Array_Field (Graph, "blocks", Where);
      Require (Length (Blocks) > 0, Where & ": blocks must be a non-empty list");

      for Index in 1 .. Length (Blocks) loop
         declare
            Block : constant JSON_Value := Value_At (Blocks, Index);
         begin
            if Block.Kind = JSON_Object_Type
              and then Has_Field (Block, "id")
              and then Field_Value (Block, "id").Kind = JSON_String_Type
            then
               Actual_Ids.Append
                 (New_Item => Get (Field_Value (Block, "id")),
                  Count    => 1);
            else
               Actual_Ids.Append (New_Item => "<missing>", Count => 1);
            end if;
            Expected_Ids.Append
              (New_Item => "bb" & Image (Index - 1),
               Count    => 1);
         end;
      end loop;

      Require
        (Actual_Ids = Expected_Ids,
         Where & ": block ids must be deterministic "
         & Render (Expected_Ids)
         & ", got "
         & Render (Actual_Ids));

      Require
        (Has_Field (Graph, "entry_bb")
         and then Field_Value (Graph, "entry_bb").Kind = JSON_String_Type
         and then Contains (Actual_Ids, Get (Field_Value (Graph, "entry_bb"))),
         Where & ": entry block id missing or invalid");

      for Index in 1 .. Length (Locals) loop
         declare
            Local       : constant JSON_Value := Value_At (Locals, Index);
            Local_Where : constant String := Where & ".locals[" & Image (Index - 1) & "]";
         begin
            Require (Local.Kind = JSON_Object_Type, Local_Where & ": local must be an object");
            Require
              (Has_Field (Local, "id")
               and then Field_Value (Local, "id").Kind = JSON_String_Type,
               Local_Where & ": missing local id");
            Require
              (Has_Field (Local, "name")
               and then Field_Value (Local, "name").Kind = JSON_String_Type,
               Local_Where & ": missing local name");
            Validate_Span (Field_Or_Null (Local, "span"), Local_Where & ".span");
            Require
              (Has_Field (Local, "type")
               and then Field_Value (Local, "type").Kind = JSON_Object_Type,
               Local_Where & ": missing local type");
            if Format = GM.Mir_V1 and then Has_Field (Local, "scope_id") then
               Require
                 (Field_Value (Local, "scope_id").Kind = JSON_String_Type,
                  Local_Where & ": invalid scope_id");
            end if;
         end;
      end loop;

      for Index in 1 .. Length (Blocks) loop
         Validate_Block
           (Value_At (Blocks, Index),
            Actual_Ids,
            Where & ".blocks[" & Image (Index - 1) & "]");
      end loop;

      if Format = GM.Mir_V2 then
         Validate_Graph_V2 (Graph, Graph_Index);
      end if;
   end Validate_Graph;

   function Validate
     (Document : GM.Mir_Document) return GM.Validation_Result
   is
      use GNATCOLL.JSON;
      Graphs : JSON_Array;
      Root_Where : constant String := "root";
   begin
      Require (Document.Root.Kind = JSON_Object_Type, "top-level payload must be an object");
      Graphs := Json_Array_Field (Document.Root, "graphs", Root_Where);
      Require (Length (Graphs) > 0, Root_Where & ": graphs must be a non-empty list");

      for Index in 1 .. Length (Graphs) loop
         Validate_Graph (Value_At (Graphs, Index), Index, Document.Format);
      end loop;

      return GM.Ok;
   exception
      when Error : Validation_Error =>
         return GM.Error (Ada.Exceptions.Exception_Message (Error));
   end Validate;

   function Validate_File
     (Path : String) return GM.Validation_Result
   is
      Loaded : constant Safe_Frontend.Mir_Json.Load_Result :=
        Safe_Frontend.Mir_Json.Load_File (Path);
   begin
      if not Loaded.Success then
         return GM.Error (FT.To_String (Loaded.Message));
      end if;

      declare
         Result : constant GM.Validation_Result := Validate (Loaded.Document);
      begin
         if Result.Success then
            return Result;
         end if;
         return GM.Error (Path & ": " & FT.To_String (Result.Message));
      end;
   end Validate_File;
end Safe_Frontend.Mir_Validate;
