# httpdicom

Reverse proxy rest serving a subset of DICOMWEB and some additions and forwarding them to
 - local DICOMWEB PACS using HTTP,
 - local DICOM PACS using WADO and SQL,
 - or another global instance of httpdicom using HTTPS
 
## subset DICOMWEB
 - wado
 - qido studies, series, instances (content-type application/dicom+json)
 - wado-rs content-type multipart/related; type="application/dicom"
 - metadata
 - wado-uri

## additions
 - encapsulated (returns the contents of attribute 00420010 with corresponding content-type)
 - zipped/wadors (returns the dicom instances zipped, instead of a multipart/related)
 - datatables/studies, patient, series (returns data source consummed by datatables without modification)

