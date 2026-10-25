--  Libfyaml.Documents.Styled - scalars built with a style, which
--  Create_Scalar can't give.
--
--  Create_Scalar leaves the style to libfyaml's emitter, which writes a
--  scalar plain even where plain YAML doesn't hold its text: "#x" reads
--  back as a comment, " x" as "x", "'x" or "- x" doesn't parse.  A
--  styled scalar is parsed instead from YAML text written here in the
--  style asked for, and the emitter keeps a parsed scalar's style.
--
--  A child of Libfyaml.Documents, as it needs the document's handle.

with Libfyaml.Nodes;

package Libfyaml.Documents.Styled is

   type Style is (Plain, Double_Quoted, Literal);

   --  A new unattached scalar in Doc holding Text, written in S:
   --  - Plain: plain if it surely reads back the same, else
   --    double-quoted;
   --  - Double_Quoted: double-quoted, escaped as needed;
   --  - Literal: a literal block (|), keeping every line break; else
   --    double-quoted, for text with no line but empty ones, or a
   --    control character but tab.
   --  Text that isn't UTF-8, which no YAML style holds, is made by
   --  Create_Scalar instead.
   function Create_Styled_Scalar (Doc : in out Document; Text : String; S : Style)
     return Nodes.Node;

end Libfyaml.Documents.Styled;
