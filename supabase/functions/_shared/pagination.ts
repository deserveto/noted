import { AppError } from './cors.ts';

// Fresh query per page and a unique, stable ordering prevent API row-cap truncation.
export async function fetchAllPages(build: () => any, key: string): Promise<any[]> {
  const rows: any[] = [];
  const size = 500;
  for (let offset = 0; ; offset += size) {
    const { data, error } = await build().order(key, { ascending: true }).range(offset, offset + size - 1);
    if (error || !data) throw new AppError('internal', `Query failed: ${error?.message ?? 'missing data'}`);
    rows.push(...data);
    if (data.length < size) return rows;
  }
}
