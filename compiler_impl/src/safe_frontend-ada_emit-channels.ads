with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;

private package Safe_Frontend.Ada_Emit.Channels is
   package SU renames Ada.Strings.Unbounded;
   package AI renames Safe_Frontend.Ada_Emit.Internal;

   subtype Emit_State is AI.Emit_State;

   procedure Render_Shared_Object_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State);
   procedure Render_Shared_Object_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State);
   procedure Render_Select_Dispatcher_Spec
     (Buffer : in out SU.Unbounded_String;
      Name   : String);
   procedure Render_Select_Dispatcher_Object_Decl
     (Buffer : in out SU.Unbounded_String;
      Name   : String);
   procedure Render_Select_Dispatcher_Body
     (Buffer : in out SU.Unbounded_String;
      Name   : String);
   procedure Render_Select_Dispatcher_Delay_Helpers
     (Buffer          : in out SU.Unbounded_String;
      Dispatcher      : String;
      Timer_Name      : String;
      Init_Helper     : String;
      Deadline_Helper : String;
      Arm_Helper      : String;
      Cancel_Helper   : String;
      Depth           : Natural := 1);
   function Channel_Uses_Sequential_Scalar_Ghost_Model
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl) return Boolean;
   procedure Render_Channel_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      Bronze   : MB.Bronze_Result);
   procedure Render_Channel_Generated_Value_Helpers
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State);
   procedure Render_Channel_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State);
end Safe_Frontend.Ada_Emit.Channels;
