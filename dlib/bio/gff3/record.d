module bio.gff3.record;

import std.conv, std.stdio, std.array, std.string, std.exception;
import std.ascii;
import bio.exceptions, util.esc_char_conv, util.split_line;

/**
 * Represents a parsed line in a GFF3 file.
 */
class Record {
  /**
   * Constructor for the Record object, arguments are passed to the
   * parser_line() method.
   */
  this(string line, bool replace_esc_chars = true) {
    if (replace_esc_chars && (line.indexOf('%') != -1))
      parse_line_and_replace_esc_chars(line);
    else
      parse_line(line);
  }

  /**
   * Parse a line from a GFF3 file and set object values.
   * The line is first split into its parts and then escaped
   * characters are replaced in those fields.
   * 
   * Setting replace_esc_chars to false will skip replacing
   * escaped characters, and make parsing significantly faster.
   */
  void parse_line(string line) {
    seqname = get_and_skip_next_field(line);
    source = get_and_skip_next_field(line);
    feature = get_and_skip_next_field(line);
    start = get_and_skip_next_field(line);
    end = get_and_skip_next_field(line);
    score = get_and_skip_next_field(line);
    strand = get_and_skip_next_field(line);
    phase = get_and_skip_next_field(line);
    auto attributes_field = get_and_skip_next_field(line);

    attributes = parse_attributes(attributes_field);
  }

  void parse_line_and_replace_esc_chars(string original_line) {
    char[] line = original_line.dup;

    seqname = cast(string) replace_url_escaped_chars( get_and_skip_next_field(line) );
    source = cast(string) replace_url_escaped_chars( get_and_skip_next_field(line) );
    feature = cast(string) replace_url_escaped_chars( get_and_skip_next_field(line) );
    start = cast(string) get_and_skip_next_field(line);
    end = cast(string) get_and_skip_next_field(line);
    score = cast(string) get_and_skip_next_field(line);
    strand = cast(string) get_and_skip_next_field(line);
    phase = cast(string) get_and_skip_next_field(line);
    auto attributes_field = get_and_skip_next_field(line);

    attributes = parse_attributes(attributes_field);
  }

  string seqname;
  string source;
  string feature;
  string start;
  string end;
  string score;
  string strand;
  string phase;
  string[string] attributes;

  /**
   * Returns the ID attribute from record attributes.
   */
  @property string id() {
    if ("ID" in attributes)
      return attributes["ID"];
    else
      return null;
  }

  /**
   * Returns the Parent attribute from record attributes
   */
  @property string parent() {
    if ("Parent" in attributes)
      return attributes["Parent"];
    else
      return null;
  }

  /**
   * Returns true if the attribute Is_circular is true for
   * this record.
   */
  @property bool is_circular() {
    if ("Is_circular" in attributes)
      return attributes["Is_circular"] == "true";
    else
      return false;
  }

  private {
    static string[string] parse_attributes(string attributes_field) {
      string[string] attributes;
      if (attributes_field[0] != '.') {
        string attribute = attributes_field; // Required for the next while loop to start
        while(attributes_field.length != 0) {
          attribute = get_and_skip_next_field(attributes_field, ';');
          if (attribute == "") continue;
          auto attribute_name = get_and_skip_next_field( attribute, '=');
          auto attribute_value = attribute;
          attributes[attribute_name] = attribute_value;
        }
      }
      return attributes;
    }

    static string[string] parse_attributes(char[] attributes_field) {
      string[string] attributes;
      if (attributes_field[0] != '.') {
        char[] attribute = attributes_field; // Required for the next while loop to start
        while(attributes_field.length != 0) {
          attribute = get_and_skip_next_field(attributes_field, ';');
          if (attribute == "") continue;
          auto attribute_name = cast(string) replace_url_escaped_chars( get_and_skip_next_field( attribute, '=') );
          auto attribute_value = cast(string) replace_url_escaped_chars( attribute );
          attributes[attribute_name] = attribute_value;
        }
      }
      return attributes;
    }
  }
}

unittest {
  writeln("Testing parseAttributes...");

  // Minimal test
  auto record = new Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1");
  assert(record.attributes == [ "ID" : "1" ]);
  // Test splitting multiple attributes
  record = new Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;Parent=45");
  assert(record.attributes == [ "ID" : "1", "Parent" : "45" ]);
  // Test if first splitting and then replacing escaped chars
  record = new Record(".\t.\t.\t.\t.\t.\t.\t.\tID%3D=1");
  assert(record.attributes == [ "ID=" : "1"]);
  // Test if parser survives trailing semicolon
  record = new Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;Parent=45;");
  assert(record.attributes == [ "ID" : "1", "Parent" : "45" ]);
  // Test for an attribute with the value of a single space
  record = new Record(".\t.\t.\t.\t.\t.\t.\t.\tID= ;");
  assert(record.attributes == [ "ID" : " " ]);
  // Test for an attribute with no value
  record = new Record(".\t.\t.\t.\t.\t.\t.\t.\tID=;");
  assert(record.attributes == [ "ID" : "" ]);
}

unittest {
  writeln("Testing GFF3 Record...");
  // Test line parsing with a normal line
  auto record = new Record("ENSRNOG00000019422\tEnsembl\tgene\t27333567\t27357352\t1.0\t+\t2\tID=ENSRNOG00000019422;Dbxref=taxon:10116;organism=Rattus norvegicus;chromosome=18;name=EGR1_RAT;source=UniProtKB/Swiss-Prot;Is_circular=true");
  with (record) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["ENSRNOG00000019422", "Ensembl", "gene", "27333567", "27357352", "1.0", "+", "2"]);
    assert(attributes == [ "ID" : "ENSRNOG00000019422", "Dbxref" : "taxon:10116", "organism" : "Rattus norvegicus", "chromosome" : "18", "name" : "EGR1_RAT", "source" : "UniProtKB/Swiss-Prot", "Is_circular" : "true"]);
  }

  // Test parsing lines with dots - undefined values
  record = new Record(".\t.\t.\t.\t.\t.\t.\t.\t.");
  with (record) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           [".", ".", ".", ".", ".", ".", ".", "."]);
    assert(attributes.length == 0);
  }

  // Test parsing lines with escaped characters
  record = new Record("EXON%3D00000131935\tASTD%25\texon%26\t27344088\t27344141\t.\t+\t.\tID=EXON%3D00000131935;Parent=TRAN%3B000000%3D17239");
  with (record) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["EXON=00000131935", "ASTD%", "exon&", "27344088", "27344141", ".", "+", "."]);
    assert(attributes == ["ID" : "EXON=00000131935", "Parent" : "TRAN;000000=17239"]);
  }

  // Test id() method/property
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1")).id == "1");
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\tID=")).id == "");
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\t.")).id is null);

  // Test isCircular() method/property
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\t.")).is_circular == false);
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\tIs_circular=false")).is_circular == false);
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\tIs_circular=true")).is_circular == true);

  // Test the Parent() method/property
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\t.")).parent is null);
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\tParent=test")).parent == "test");
  assert((new Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;Parent=test;")).parent == "test");
}

