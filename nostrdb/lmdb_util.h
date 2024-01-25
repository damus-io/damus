
// Define callback function type
typedef bool (*lmdb_callback_t)(const MDB_val*, const MDB_val*);


int lmdb_foreach(MDB_txn *txn, MDB_dbi dbi, MDB_val *start, MDB_val *start_dup, callback_t cb, bool reverse) {
	int success = 0;
	MDB_cursor *cursor;

	// Open a cursor on the provided transaction and database
	int rc = mdb_cursor_open(txn, dbi, &cursor);

	if (rc != 0)
		return 0;

	MDB_val k = *start, v = *start_dup;
	MDB_cursor_op op = reverse ? MDB_PREV : MDB_NEXT;

	// If we're scanning in reverse...
	if (reverse) {
		// Try to position the cursor at the first key-value pair where
		// both the key and the value are greater than or equal to our
		// starting point.
		rc = mdb_cursor_get(cursor, &k, &v, MDB_GET_BOTH_RANGE);
		if (rc == 0) {
			if (v.mv_size != start_dup->mv_size ||
			    memcmp(v.mv_data, start_dup->mv_data, v.mv_size) != 0) {
				// If the value doesn't match our starting
				// point, step back to the previous record.
				if (mdb_cursor_get(cursor, &k, &v, MDB_PREV) != 0)
					goto cleanup;
			}
		} else {
			// If we couldn't find a record that matches both our
			// starting key and value, try to find a record that
			// matches just our starting key.
			if (mdb_cursor_get(cursor, &k, &v, MDB_SET) == 0) {
				// If we find a match, move to the last value
				// for this key, since we're scanning in
				// reverse.
				if (mdb_cursor_get(cursor, &k, &v, MDB_LAST_DUP) != 0)
					goto cleanup;
			} else {
				// If we can't find a record with our starting
				// key, try to find the first record with a key
				// greater than our starting key.
				if (mdb_cursor_get(cursor, &k, &v, MDB_SET_RANGE) == 0) {
					// If we find such a record, step back
					// to the previous record.
					if (mdb_cursor_get(cursor, &k, &v, MDB_PREV) != 0)
						goto cleanup;
				} else {
					// If we can't even find a record with
					// a key greater than our starting key,
					// fall back to starting from the last
					// record in the database.
					if (mdb_cursor_get(cursor, &k, &v, MDB_LAST) != 0)
						goto cleanup;
				}
			}
		}
		// If we're not scanning in reverse...
		else {
			// Try to position the cursor at the first key-value
			// pair where both the key and the value are greater
			// than or equal to our starting point.
			if (mdb_cursor_get(cursor, &k, &v, MDB_SET) != 0) {
				// If we couldn't find a record that matches
				// both our starting key and value, try to find
				// a record that matches just our starting key.
				if (mdb_cursor_get(cursor, &k, &v, MDB_SET_RANGE) != 0)
					goto cleanup;

				// If we can't find a record with our starting
				// key, try to find the first record with a key
				// greater than our starting key.
				if (mdb_cursor_get(cursor, &k, &v, MDB_FIRST_DUP) != 0)
					goto cleanup;
			}
		}
	}

	// Whether we're scanning forward or backward, start the actual
	// iteration, moving one step at a time in the appropriate direction
	// and calling the provided callback for each record.
	do {
		if (!cb(&k, &v))
			goto cleanup;
	} while (mdb_cursor_get(cursor, &k, &v, op) == 0);

	// If we make it through the entire iteration without the callback
	// returning false, return true to signal success.
	success = 1;

cleanup:
	mdb_cursor_close(cursor);
	return success;
}


