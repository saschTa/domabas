final class DocumentCapabilities {
  const DocumentCapabilities({
    this.read = false,
    this.search = false,
    this.download = false,
    this.readThumbnails = false,
    this.create = false,
    this.update = false,
    this.readOcr = false,
    this.updateOcr = false,
    this.delete = false,
    this.retry = false,
    this.unlock = false,
  });

  final bool read;
  final bool search;
  final bool download;
  final bool readThumbnails;
  bool get preview => download && readThumbnails;
  final bool create;
  final bool update;
  final bool readOcr;
  final bool updateOcr;
  final bool delete;
  final bool retry;
  final bool unlock;
}
