import { Router } from 'express';
import { getYtStreamUrl } from '../services/ytService.js';

const router = Router();

router.get('/stream', async (req, res) => {
  const { v } = req.query;
  
  if (!v) {
    return res.status(400).json({
      success: false,
      error: 'Missing required parameter: v (YouTube Video ID)'
    });
  }
  
  try {
    const result = await getYtStreamUrl(v);
    
    res.json({
      success: true,
      provider: 'youtube',
      ...result
    });
    
  } catch (error) {
    console.error('YouTube stream error:', error.message);
    res.status(500).json({
      success: false,
      error: 'Failed to extract YouTube stream',
      details: error.message
    });
  }
});

export default router;