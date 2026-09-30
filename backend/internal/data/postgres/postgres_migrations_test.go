package postgres

import (
	"strings"
	"testing"
	"testing/fstest"
)

func TestReadMigrations(t *testing.T) {
	for _, name := range []string{"000_bad.sql", "01_short.sql", "1000_long.sql", "001_UPPER.sql", "001_.sql", "001_bad-name.sql"} {
		t.Run(name, func(t *testing.T) {
			if _, err := readMigrations(fstest.MapFS{"migrations/" + name: {Data: []byte("SELECT 1")}}); err == nil {
				t.Fatal("accepted invalid filename")
			}
		})
	}
	if _, err := readMigrations(fstest.MapFS{"migrations/001_one.sql": {}, "migrations/001_two.sql": {}}); err == nil {
		t.Fatal("accepted duplicate number")
	}
	files, err := readMigrations(fstest.MapFS{"migrations/010_ten.sql": {Data: []byte("SELECT 10;\n")}, "migrations/002_two.sql": {Data: []byte("SELECT 2;")}})
	if err != nil {
		t.Fatal(err)
	}
	if files[0].number != 2 || files[1].number != 10 {
		t.Fatal("numeric order or gaps rejected")
	}
	changed, err := readMigrations(fstest.MapFS{"migrations/002_two.sql": {Data: []byte("SELECT 2;\n")}})
	if err != nil {
		t.Fatal(err)
	}
	if changed[0].checksum == files[0].checksum {
		t.Fatal("checksum ignored exact bytes")
	}
}

func TestValidateHistory(t *testing.T) {
	files, err := readMigrations(migrations)
	if err != nil {
		t.Fatal(err)
	}
	if files[0].checksum != originalMigrationChecksum {
		t.Fatal("original migration was modified")
	}
	checksum := files[0].checksum
	for _, legacy := range []bool{false, true} {
		if err := validateHistory(files, nil, legacy); err != nil {
			t.Fatal(err)
		}
		if err := validateHistory(files, []postgresAppliedMigration{{"001_documents.sql", &checksum}}, legacy); err != nil {
			t.Fatal(err)
		}
	}
	for _, history := range [][]postgresAppliedMigration{
		{{"002_unknown.sql", &checksum}}, {{"001_renamed.sql", &checksum}}, {{"001_documents.sql", nil}},
	} {
		if err := validateHistory(files, history, false); err == nil {
			t.Fatalf("accepted history %+v", history)
		}
	}
	changed := strings.Repeat("0", 64)
	if err := validateHistory(files, []postgresAppliedMigration{{"001_documents.sql", &changed}}, false); err == nil {
		t.Fatal("accepted changed checksum")
	}
	if err := validateHistory(files, []postgresAppliedMigration{{"001_documents.sql", nil}, {"002_unknown.sql", nil}}, true); err == nil {
		t.Fatal("accepted unknown legacy history")
	}
	files[0].checksum = changed
	if err := validateHistory(files, nil, true); err == nil {
		t.Fatal("accepted changed legacy file")
	}
}
