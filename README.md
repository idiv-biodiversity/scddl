BLAST Download
==============

Downloads NCBI's BLAST databases. Originally intended for High-Performance Cluster systems to provide the databases within globally readable shares so all user groups can access the same databases.

Features
--------

-   existing files are not overwritten

    All running jobs would have inconsistent results if files would be updated in place.
    
-   downloaded datasets are tagged with the download date
    
    Each consistent download is tagged with the local date of the download. You can access these datasets via:
    
        blastn -db /data/db/blast/nt-2016-09-01 ...
        
    This also allows for **reproducible research**, which you would not be able to do with in place updates of the database files.

-   md5s are rigorously checked

    If one md5 does not match the entire update is canceled. The md5s are downloaded prior to the tarballs. If you download each tarball individually and the respective md5 after, you will never have a consistent download of the entire dataset, because NCBI updates the database in place on their ftp server. Thus, the only way to have a consistent dataset is to download all the md5s in advance and the tarballs after it and throw everything away and start fresh if something does not match.

-   you can specify the download directory

    Intended to be a globally readable share. This way, all users can access the same files instead of having to download the files to their individual personal or group directories. This approach has a few advantages:
    
    - no user or group quotas are utilized
    - a single copy of the database, not multiple copies for each user or group
    - a single copy can also be cached better, thus provided faster by the cluster file system, which would not be the case with individual copies

-   output is sent to syslog with the tag **blastdl**

    To get the log, type e.g.:

        journalctl -t blastdl

Usage
-----

Intended to be used as cron jobs, e.g.:

```
@monthly time bash /path/to/blastdl/blastdl.sh nr /data/db/blast
@monthly time bash /path/to/blastdl/blastdl.sh nt /data/db/blast
```
