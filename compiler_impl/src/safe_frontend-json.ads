with Safe_Frontend.Types;

package Safe_Frontend.Json is
   function Escape (Item : String) return String;
   function Bool_Literal (Item : Boolean) return String;
   function Quote (Item : String) return String;
   function Quote (Item : Safe_Frontend.Types.UString) return String;
   function Span_Object (Span : Safe_Frontend.Types.Source_Span) return String;
end Safe_Frontend.Json;
