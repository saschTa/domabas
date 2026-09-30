package postgres

type postgresMigration struct {
	version  string
	number   int
	sql      string
	checksum string
}

type postgresAppliedMigration struct {
	version  string
	checksum *string
}

type postgresLedgerColumn struct {
	name, kind   string
	required     bool
	defaultValue string
}
