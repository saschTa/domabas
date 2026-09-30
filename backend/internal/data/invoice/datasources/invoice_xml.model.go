package datasources

import "encoding/xml"

type invoiceXmlNode struct {
	name     xml.Name
	attrs    []xml.Attr
	text     string
	children []*invoiceXmlNode
}
