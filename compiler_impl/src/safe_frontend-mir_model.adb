package body Safe_Frontend.Mir_Model is
   function Image (Item : Mir_Format_Kind) return String is
   begin
      case Item is
         when Mir_V1 =>
            return "mir-v1";
         when Mir_V2 =>
            return "mir-v2";
      end case;
   end Image;

   function Image (Item : Ownership_Effect_Kind) return String is
   begin
      case Item is
         when Ownership_Invalid =>
            return "<invalid>";
         when Ownership_None =>
            return "None";
         when Ownership_Move =>
            return "Move";
         when Ownership_Borrow =>
            return "Borrow";
         when Ownership_Observe =>
            return "Observe";
      end case;
   end Image;

   function Image (Item : Expr_Kind) return String is
   begin
      case Item is
         when Expr_Unknown =>
            return "<unknown>";
         when Expr_Int =>
            return "int";
         when Expr_Real =>
            return "real";
         when Expr_String =>
            return "string";
         when Expr_Char =>
            return "char";
         when Expr_Bool =>
            return "bool";
         when Expr_Null =>
            return "null";
         when Expr_Ident =>
            return "ident";
         when Expr_Select =>
            return "select";
         when Expr_Resolved_Index =>
            return "resolved_index";
         when Expr_Conversion =>
            return "conversion";
         when Expr_Call =>
            return "call";
         when Expr_Allocator =>
            return "allocator";
         when Expr_Aggregate =>
            return "aggregate";
         when Expr_Annotated =>
            return "annotated";
         when Expr_Unary =>
            return "unary";
         when Expr_Binary =>
            return "binary";
      end case;
   end Image;

   function Image (Item : Op_Kind) return String is
   begin
      case Item is
         when Op_Unknown =>
            return "<unknown>";
         when Op_Scope_Enter =>
            return "scope_enter";
         when Op_Scope_Exit =>
            return "scope_exit";
         when Op_Assign =>
            return "assign";
         when Op_Call =>
            return "call";
         when Op_Channel_Send =>
            return "channel_send";
         when Op_Channel_Receive =>
            return "channel_receive";
         when Op_Channel_Try_Send =>
            return "channel_try_send";
         when Op_Channel_Try_Receive =>
            return "channel_try_receive";
         when Op_Delay =>
            return "delay";
      end case;
   end Image;

   function Image (Item : Terminator_Kind) return String is
   begin
      case Item is
         when Terminator_Unknown =>
            return "<unknown>";
         when Terminator_Jump =>
            return "jump";
         when Terminator_Branch =>
            return "branch";
         when Terminator_Return =>
            return "return";
         when Terminator_Select =>
            return "select";
      end case;
   end Image;

   function Ok return Validation_Result is
   begin
      return (Success => True);
   end Ok;

   function Error (Message : String) return Validation_Result is
   begin
      return (Success => False, Message => FT.To_UString (Message));
   end Error;
end Safe_Frontend.Mir_Model;
