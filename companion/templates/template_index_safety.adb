--  Verified Emission Template: Safe Array Indexing
--  See template_index_safety.ads for clause references.

pragma SPARK_Mode (On);

with Safe_PO; use Safe_PO;

package body Template_Index_Safety
  with SPARK_Mode => On
is

   -------------------------------------------------------------------
   --  Pattern 1: Direct index with literal
   --
   --  Emission pattern:
   --    arr[1] -> Safe_Index(1, 100, 1); Narrow_Indexing(1, range); arr(1)
   --  The literal 1 is trivially in bounds 1..100.
   -------------------------------------------------------------------
   function Read_First (Arr : Data_Array) return Integer is
   begin
      --  PO hook: bounds check for index 1 in array 1..100.
      Safe_Index (Long_Long_Integer (Data_Index'First),
                  Long_Long_Integer (Data_Index'Last),
                  1);

      --  PO hook: narrowing check for index value.
      Narrow_Indexing (1, Data_Index_Range);

      return Arr (1);
   end Read_First;

   -------------------------------------------------------------------
   --  Pattern 2: Loop index (bounds from loop range)
   --
   --  Emission pattern:
   --    for i in arr.bounds { sum += arr[i]; }
   --  The loop variable i is in Data_Index range, so indexing is safe.
   --  The compiler emits Safe_Index + Narrow_Indexing for each iteration.
   -------------------------------------------------------------------
   function Sum (Arr : Data_Array) return Long_Long_Integer is
      Total : Long_Long_Integer := 0;
   begin
      for I in Data_Index loop
         --  PO hooks: index I is in 1..100 by loop range.
         Safe_Index (Long_Long_Integer (Data_Index'First),
                     Long_Long_Integer (Data_Index'Last),
                     Long_Long_Integer (I));
         Narrow_Indexing (Long_Long_Integer (I), Data_Index_Range);

         pragma Loop_Invariant
           (Total >=
              Long_Long_Integer (I - 1)
              * Long_Long_Integer (Integer'First)
            and then
            Total <=
              Long_Long_Integer (I - 1)
              * Long_Long_Integer (Integer'Last));

         Total := Total + Long_Long_Integer (Arr (I));
      end loop;

      return Total;
   end Sum;

   -------------------------------------------------------------------
   --  Pattern 3: Computed index with precondition
   --
   --  Emission pattern:
   --    fn read_at(arr: [100]Int, idx: Int) -> Int
   --      requires idx >= 1 and idx <= 100
   --  The precondition establishes bounds for the Safe_Index check.
   -------------------------------------------------------------------
   function Read_At
     (Arr : Data_Array;
      Idx : Integer) return Integer
   is
   begin
      --  PO hooks: index is in bounds (proved from precondition).
      Safe_Index (Long_Long_Integer (Data_Index'First),
                  Long_Long_Integer (Data_Index'Last),
                  Long_Long_Integer (Idx));
      Narrow_Indexing (Long_Long_Integer (Idx), Data_Index_Range);

      return Arr (Idx);
   end Read_At;

   -------------------------------------------------------------------
   --  Pattern 4: Conditional indexing with runtime guard
   --
   --  Emission pattern:
   --    if idx >= 1 and idx <= 100 { arr[idx] } else { default }
   --  Inside the guard, Safe_Index is provable.
   -------------------------------------------------------------------
   function Safe_Read_At
     (Arr     : Data_Array;
      Idx     : Integer;
      Default : Integer) return Integer
   is
   begin
      if Idx >= 1 and then Idx <= 100 then
         --  Inside guard: bounds are established.
         Safe_Index (Long_Long_Integer (Data_Index'First),
                     Long_Long_Integer (Data_Index'Last),
                     Long_Long_Integer (Idx));
         Narrow_Indexing (Long_Long_Integer (Idx), Data_Index_Range);

         return Arr (Idx);
      else
         return Default;
      end if;
   end Safe_Read_At;

end Template_Index_Safety;
