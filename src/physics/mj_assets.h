#pragma once
#include <mujoco/mujoco.h>
#include <godot_cpp/classes/xml_parser.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <functional>
#include <vector>
namespace godot {
inline String gmj_spec_xml(const mjSpec*s){char error[2048]={};int n=mj_saveXMLString(s,nullptr,0,error,sizeof(error));if(n<=0)return {};std::vector<char>b(n+1);if(mj_saveXMLString(s,b.data(),b.size(),error,sizeof(error)))return {};return String::utf8(b.data());}
// Never dereference mjStringVec as a host STL container: the distributed MuJoCo
// binary may use another C++ standard-library ABI. Canonical XML is the boundary.
inline String gmj_asset_xml(const String &xml,const std::function<String(const String&)>&path){
 Ref<XMLParser> parser;parser.instantiate();if(parser->open_buffer(xml.to_utf8_buffer())!=OK)return {};
 String out;
 while(parser->read()==OK){auto type=parser->get_node_type();
  if(type==XMLParser::NODE_ELEMENT){String tag=parser->get_node_name();out+="<"+tag;
   for(int i=0;i<parser->get_attribute_count();++i){String key=parser->get_attribute_name(i),value=parser->get_attribute_value(i);
    if((tag=="mesh"||tag=="texture"||tag=="hfield"||tag=="skin")&&(key=="file"||key=="fileleft"||key=="fileright"||key=="fileup"||key=="filedown"||key=="filefront"||key=="fileback")&&!value.is_empty())value=path(value);
    out+=" "+key+"=\""+value.xml_escape(true)+"\"";
   }out+=parser->is_empty()?"/>":">";
  }else if(type==XMLParser::NODE_ELEMENT_END)out+="</"+parser->get_node_name()+">";
  else if(type==XMLParser::NODE_TEXT)out+=parser->get_node_data().xml_escape();
 }return out;
}
}
