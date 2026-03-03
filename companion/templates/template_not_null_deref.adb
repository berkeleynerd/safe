--  Verified Emission Template: Not-Null Assertion Before Dereference
--  See template_not_null_deref.ads for clause references.

pragma SPARK_Mode (On);

with Safe_PO; use Safe_PO;

package body Template_Not_Null_Deref
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Pattern 1: Dereference to read
   --
   --  Emission pattern:
   --    1. Assert not null (Not_Null_Ptr ghost call)
   --    2. Dereference (Safe_Deref ghost call)
   --    3. Read the value
   -------------------------------------------------------------------
   function Deref_Read (P : Ptr_Model) return Integer is
   begin
      --  PO hook: assert pointer is not null before dereference.
      Not_Null_Ptr (P.Is_Null);

      --  PO hook: safe dereference.
      Safe_Deref (P.Is_Null);

      --  Model: return P.all.Value
      return P.Value;
   end Deref_Read;

   -------------------------------------------------------------------
   --  Pattern 2: Dereference to write
   --
   --  Emission pattern:
   --    1. Assert not null
   --    2. Write through the pointer
   -------------------------------------------------------------------
   procedure Deref_Write
     (P         : in out Ptr_Model;
      New_Value : Integer)
   is
   begin
      --  PO hook: assert pointer is not null before dereference.
      Not_Null_Ptr (P.Is_Null);

      --  PO hook: safe dereference.
      Safe_Deref (P.Is_Null);

      --  Model: P.all.Value := New_Value
      P.Value := New_Value;
   end Deref_Write;

   -------------------------------------------------------------------
   --  Pattern 3: Conditional dereference (guarded)
   --
   --  When the compiler cannot statically prove non-null, it emits
   --  a runtime guard. Inside the guard, the Not_Null_Ptr / Safe_Deref
   --  PO hooks are provable because the guard establishes not-null.
   -------------------------------------------------------------------
   function Safe_Read (P : Ptr_Model; Default : Integer) return Integer is
   begin
      if not P.Is_Null then
         --  Inside guard: not P.Is_Null is established.
         Not_Null_Ptr (P.Is_Null);
         Safe_Deref (P.Is_Null);
         return P.Value;
      else
         return Default;
      end if;
   end Safe_Read;

end Template_Not_Null_Deref;
