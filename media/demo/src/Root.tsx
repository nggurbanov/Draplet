import {Composition} from 'remotion';
import {DrapletDemo} from './Composition';
export const RemotionRoot: React.FC = () => <Composition id="DrapletDemo" component={DrapletDemo} durationInFrames={540} fps={30} width={1440} height={600} defaultProps={{accent: '#E58B60'}} />;
