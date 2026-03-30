pragma SPARK_Mode (On);

generic
   type Target_Type is private;
   type Access_Type is access Target_Type;
package Safe_Ownership_RT is
   function Allocate (Value : Target_Type) return not null Access_Type
     with Post => Allocate'Result /= null;

   procedure Free (Value : in out Access_Type)
     with Always_Terminates,
          Post => Value = null;

   procedure Dispose (Value : in out Access_Type) renames Free;
end Safe_Ownership_RT;
