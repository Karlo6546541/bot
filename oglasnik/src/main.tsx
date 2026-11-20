import { render } from 'preact';
import { App } from './app';
import { presretniPoveznice } from './lib/router';
import './styles.css';

// GitHub Pages: 404.html sprema traženu adresu pa ovdje vraćamo pravu.
presretniPoveznice();
render(<App />, document.getElementById('app')!);
