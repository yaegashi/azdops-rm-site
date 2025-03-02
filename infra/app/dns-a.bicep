param dnsZoneName string
param dnsRecordName string
param a string
param wildcard bool = false

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
}

resource dnsRecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: dnsZone
  name: dnsRecordName
  properties: {
    TTL: 3600
    ARecords: [{ ipv4Address: a }]
  }
}

resource dnsRecordWildcard 'Microsoft.Network/dnsZones/A@2018-05-01' = if (wildcard) {
  parent: dnsZone
  name: dnsRecordName == '@' ? '*' : '*.${dnsRecordName}'
  properties: {
    TTL: 3600
    ARecords: [{ ipv4Address: a }]
  }
}
