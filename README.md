# httpdicom

Reverse proxy rest which provides a subset of DICOMWEB services (and some additional ones) and forwards queries to
 - DICOMWEB PACS using HTTP,
 - DICOM PACS using WADO and SQL,
 - or another instance of httpdicom using HTTPS
 
## subset DICOMWEB
 - qido studies, series, instances (content-type application/dicom+json)
   - no proxying of studies/{StudyIUID}/series
   - no proxying of studies/{StudyIUID}/series/{SeriesIUID}/instances
 - wado-rs content-type multipart/related; type="application/dicom"
 - metadata
 - wado-uri

## additions
 - encapsulated (returns the contents of attribute 00420010 with corresponding content-type)
 - zipped/wadors (returns the dicom instances zipped, instead of a multipart/related)
 - datatables/studies, patient, series (returns data source consummed by datatables without modification)
 - wado-rs content-type multipart/related; type="application/dicom" /export
 - wado-uri /export

