import m0000 from './20261101143747_init/migration.sql';
import m0001 from './20261101234400_pair_room/migration.sql';
import m0002 from './20261101234902_delivery/migration.sql';
import m0003 from './20261102014604_idempotency_key/migration.sql';
import m0004 from './20261104232213_cat/migration.sql';
import m0005 from './20261105014114_activity/migration.sql';
import m0006 from './20261105032849_owned_ink/migration.sql';

  export default {
    migrations: {
      "20261101143747_init": m0000,
"20261101234400_pair_room": m0001,
"20261101234902_delivery": m0002,
"20261102014604_idempotency_key": m0003,
"20261104232213_cat": m0004,
"20261105014114_activity": m0005,
"20261105032849_owned_ink": m0006
}
  }
  