with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;

private package Safe_Frontend.Ada_Emit.Proofs is
   package SU renames Ada.Strings.Unbounded;
   package AI renames Safe_Frontend.Ada_Emit.Internal;

   subtype Emit_State is AI.Emit_State;

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
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return String;
   function Render_Global_Aspect
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Summary    : MB.Graph_Summary;
      Bronze     : MB.Bronze_Result) return String;
   function Render_Depends_Aspect
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Summary    : MB.Graph_Summary;
      Bronze     : MB.Bronze_Result) return String;
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
   function Render_Subprogram_Aspects
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Bronze     : MB.Bronze_Result;
      State      : in out Emit_State) return String;
   function Render_Expression_Function_Image
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String;
   procedure Render_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State);
   procedure Render_Task_Body
     (Buffer    : in out SU.Unbounded_String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Task_Item : CM.Resolved_Task;
      State     : in out Emit_State);
end Safe_Frontend.Ada_Emit.Proofs;
