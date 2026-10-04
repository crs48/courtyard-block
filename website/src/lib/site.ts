export const repository = 'https://github.com/crs48/courtyard-block';
export const base = import.meta.env.BASE_URL.replace(/\/$/, '');
export const url = (path = '') => `${base}/${path.replace(/^\//, '')}`;
export const source = (path: string) => `${repository}/blob/main/${path.split('/').map(encodeURIComponent).join('/')}`;
